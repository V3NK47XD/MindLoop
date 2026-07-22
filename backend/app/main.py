import os
import shutil
import uuid
import logging
import json
import zipfile
from datetime import datetime
from pathlib import Path
from contextlib import asynccontextmanager
from pydantic import BaseModel
from fastapi import FastAPI, UploadFile, File, HTTPException, Form, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.config import settings
from app.routers import pairing, sync
from app.services.pdf_service import extract_pdf_content
from app.services.generator import generate_flashcards_from_pdf

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger(__name__)

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: Initialize UDP broadcast discovery listener
    logger.info("Starting UDP Broadcast Discovery Listener...")
    pairing.start_udp_broadcast_listener()
    yield
    # Shutdown: Clean up UDP listener
    logger.info("Stopping UDP Broadcast Discovery Listener...")
    pairing.stop_udp_broadcast_listener()

app = FastAPI(
    title="MindLoop PC API Server",
    description="Backend API supporting flashcard generation, network discovery, and mobile sync.",
    version="1.0.0",
    lifespan=lifespan
)

# CORS setup for frontend local development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Register routers
app.include_router(pairing.router)
app.include_router(sync.router)

@app.post("/api/generate/pdf")
async def generate_from_pdf(
    file: UploadFile = File(...),
    model: str = Form(None),
    existing_tags: str = Form(None)
):
    """
    Uploads a PDF, extracts pages + images, calls Gemini, and saves .flash files.
    """
    if not file.filename.endswith(".pdf"):
        raise HTTPException(status_code=400, detail="Only PDF files are supported.")
        
    api_key = settings.GEMINI_API_KEY
    if not api_key:
        raise HTTPException(
            status_code=400,
            detail="Gemini API Key is not set. Please add it to backend/.env"
        )
        
    selected_model = model or settings.GEMINI_MODEL
    
    # Parse existing tags if provided
    tags_list = []
    if existing_tags:
        try:
            tags_list = json.loads(existing_tags)
        except Exception:
            pass
    
    # Create unique session paths for temporary file storage
    session_id = str(uuid.uuid4())
    session_dir = settings.temp_path / session_id
    session_dir.mkdir(parents=True, exist_ok=True)
    
    pdf_temp_path = session_dir / file.filename
    
    try:
        # 1. Save uploaded file to temp path
        with open(pdf_temp_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
            
        # 2. Extract PDF contents (text + images)
        logger.info(f"Extracting contents from {file.filename}...")
        pages_data = extract_pdf_content(pdf_temp_path, session_dir)
        
        # 3. Trigger Gemini generation and .flash packaging
        logger.info(f"Generating flashcards for {file.filename} using {selected_model}...")
        card_hashes = generate_flashcards_from_pdf(
            api_key=api_key,
            model_name=selected_model,
            pdf_path=pdf_temp_path,
            pages_data=pages_data,
            temp_img_dir=session_dir,
            storage_dir=settings.storage_path,
            existing_tags=tags_list
        )
        
        return {
            "status": "success",
            "pdf_name": file.filename,
            "card_hashes": card_hashes,
            "count": len(card_hashes)
        }
        
    except Exception as e:
        logger.error(f"Failed to generate flashcards from PDF: {e}")
        raise HTTPException(status_code=500, detail=str(e))
        
    finally:
        # Clean up session directory
        try:
            if session_dir.exists():
                shutil.rmtree(session_dir)
                logger.info(f"Cleaned up session directory {session_id}")
        except Exception as cleanup_err:
            logger.warning(f"Failed to clean up temp files: {cleanup_err}")

class ManualCardCreate(BaseModel):
    question: str
    answer: str
    tags: list[str]
    source_pdf: str = "Manual"
    pdf_ref_line: int = 0

class CardUpdate(BaseModel):
    question: str
    answer: str
    tags: list[str]
    source_pdf: str
    pdf_ref_line: int
    attachments: list[str] = []

from app.services.generator import generate_card_id

@app.post("/api/cards")
def create_card_manually(
    card_data: str = Form(...),
    images: list[UploadFile] = File([])
):
    """
    Creates a new flashcard manually and packages it into <card_id>.flash using a 128-char random ID.
    """
    try:
        data_dict = json.loads(card_data)
        card_data_parsed = ManualCardCreate(**data_dict)
    except Exception as parse_err:
        raise HTTPException(status_code=400, detail=f"Invalid card data: {parse_err}")

    if len(card_data_parsed.tags) > 1:
        raise HTTPException(
            status_code=400,
            detail="A card can have at most exactly 1 tag."
        )
        
    # Generate 128-character unique random ID
    card_id = generate_card_id()
    created_at = datetime.utcnow().isoformat() + "Z"
    
    # Save target path
    flash_filename = f"{card_id}.flash"
    flash_path = settings.storage_path / flash_filename
    
    # Standardize attachments paths
    attachments = []
    
    # Build metadata.json
    metadata = {
        "id": card_id,
        "question": card_data_parsed.question,
        "created_at": created_at,
        "tags": card_data_parsed.tags,
        "source_pdf": card_data_parsed.source_pdf,
        "pdf_ref_line": card_data_parsed.pdf_ref_line,
        "attachments": attachments
    }
    
    try:
        os.makedirs(settings.storage_path, exist_ok=True)
        
        # Save uploaded images to a temp folder first to write to zip
        temp_dir = settings.temp_path / f"new_{card_id}"
        temp_dir.mkdir(parents=True, exist_ok=True)
        
        for img in images:
            if img.filename:
                target_img_path = temp_dir / img.filename
                with open(target_img_path, "wb") as buffer:
                    shutil.copyfileobj(img.file, buffer)
                attachments.append(f"assets/{img.filename}")
                
        with zipfile.ZipFile(flash_path, "w", zipfile.ZIP_DEFLATED) as zip_file:
            zip_file.writestr("metadata.json", json.dumps(metadata, indent=2))
            zip_file.writestr("content.md", card_data_parsed.answer)
            
            # Write assets
            for img_name in os.listdir(temp_dir):
                zip_file.write(temp_dir / img_name, arcname=f"assets/{img_name}")
                
        # Clean up temp folder
        if temp_dir.exists():
            shutil.rmtree(temp_dir)
            
        logger.info(f"Manually created and packaged flashcard {card_id}")
        return {"status": "success", "card_hash": card_id}
    except Exception as e:
        logger.error(f"Failed to save manual flashcard: {e}")
        try:
            temp_dir = settings.temp_path / f"new_{card_id}"
            if temp_dir.exists():
                shutil.rmtree(temp_dir)
        except:
            pass
        raise HTTPException(status_code=500, detail=str(e))

@app.put("/api/cards/{card_hash}")
def update_card(
    card_hash: str,
    card_data: str = Form(...),
    images: list[UploadFile] = File([])
):
    """
    Edits an existing flashcard in-place preserving its permanent 128-character ID.
    Rewrites content.md, metadata.json, and assets inside {card_id}.flash.
    """
    try:
        data_dict = json.loads(card_data)
        card_data_parsed = CardUpdate(**data_dict)
    except Exception as parse_err:
        raise HTTPException(status_code=400, detail=f"Invalid card data: {parse_err}")

    if len(card_data_parsed.tags) > 1:
        raise HTTPException(
            status_code=400,
            detail="A card can have at most exactly 1 tag."
        )
        
    flash_path = settings.storage_path / f"{card_hash}.flash"
    
    existing_created_at = datetime.utcnow().isoformat() + "Z"
    existing_source_pdf = card_data_parsed.source_pdf
    temp_dir = settings.temp_path / f"edit_{card_hash}"
    temp_dir.mkdir(parents=True, exist_ok=True)
    
    # Read existing zip assets and metadata if available
    if flash_path.exists():
        try:
            with zipfile.ZipFile(flash_path, "r") as old_zip:
                metadata_str = old_zip.read("metadata.json").decode("utf-8")
                old_metadata = json.loads(metadata_str)
                existing_created_at = old_metadata.get("created_at", existing_created_at)
                existing_source_pdf = old_metadata.get("source_pdf", existing_source_pdf)
                
                # Extract any assets
                for name in old_zip.namelist():
                    if name.startswith("assets/"):
                        old_zip.extract(name, temp_dir)
        except Exception as zip_err:
            logger.warning(f"Error reading existing card zip: {zip_err}")
                
    extracted_assets_dir = temp_dir / "assets"
    active_attachments = []
    if extracted_assets_dir.exists():
        for asset_file in list(extracted_assets_dir.glob("*")):
            rel_name = f"assets/{asset_file.name}"
            if rel_name in card_data_parsed.attachments:
                active_attachments.append(rel_name)
            else:
                os.remove(asset_file)
                
    # Save newly uploaded images
    for img in images:
        if img.filename:
            extracted_assets_dir.mkdir(parents=True, exist_ok=True)
            target_img_path = extracted_assets_dir / img.filename
            with open(target_img_path, "wb") as buffer:
                shutil.copyfileobj(img.file, buffer)
            rel_name = f"assets/{img.filename}"
            if rel_name not in active_attachments:
                active_attachments.append(rel_name)
                
    # Build metadata.json using fixed card_hash ID
    metadata = {
        "id": card_hash,
        "question": card_data_parsed.question,
        "created_at": existing_created_at,
        "tags": card_data_parsed.tags,
        "source_pdf": existing_source_pdf,
        "pdf_ref_line": card_data_parsed.pdf_ref_line,
        "attachments": active_attachments
    }
    
    try:
        os.makedirs(settings.storage_path, exist_ok=True)
        # Package into ZIP overwriting in-place
        with zipfile.ZipFile(flash_path, "w", zipfile.ZIP_DEFLATED) as new_zip:
            new_zip.writestr("metadata.json", json.dumps(metadata, indent=2))
            new_zip.writestr("content.md", card_data_parsed.answer)
            
            # Re-add active assets
            if extracted_assets_dir.exists():
                for asset_file in extracted_assets_dir.glob("*"):
                    new_zip.write(asset_file, arcname=f"assets/{asset_file.name}")
                    
        logger.info(f"Overwrote flashcard {card_hash} in-place.")
        
        # Clean up temp edit directory
        if temp_dir.exists():
            shutil.rmtree(temp_dir)

        from app.routers.pairing import notify_listeners
        notify_listeners()
            
        return {"status": "success", "card_hash": card_hash}
    except Exception as e:
        logger.error(f"Failed to edit flashcard: {e}")
        try:
            temp_dir = settings.temp_path / f"edit_{card_hash}"
            if temp_dir.exists():
                shutil.rmtree(temp_dir)
        except:
            pass
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/cards")
def list_cards():
    """List all flashcards stored on the PC."""
    try:
        return sync.get_pc_library()
    except Exception as e:
        logger.error(f"Error listing cards: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/api/cards/{card_hash}")
def delete_card(card_hash: str):
    """Delete a flashcard from the PC local library."""
    file_path = settings.storage_path / f"{card_hash}.flash"
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="Flashcard not found")
        
    try:
        os.remove(file_path)
        logger.info(f"Deleted card {card_hash} from storage.")
        return {"status": "success", "deleted_card_id": card_hash}
    except Exception as e:
        logger.error(f"Failed to delete card file: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/cards/{card_hash}/content")
def get_card_content(card_hash: str):
    """Retrieves the full card details including the answer body from content.md or device metadata cache."""
    import zipfile
    import json
    file_path = settings.storage_path / f"{card_hash}.flash"
    if file_path.exists():
        try:
            with zipfile.ZipFile(file_path, "r") as zip_file:
                metadata_str = zip_file.read("metadata.json").decode("utf-8")
                metadata = json.loads(metadata_str)
                answer_str = zip_file.read("content.md").decode("utf-8")
                metadata["id"] = card_hash
                metadata["answer"] = answer_str
                return metadata
        except Exception as e:
            logger.error(f"Failed to read card content for {card_hash}: {e}")
            raise HTTPException(status_code=500, detail=str(e))

    # Dynamic Fallback: Check if card content exists in mobile device metadata cache
    for dev_id, meta_map in sync.device_metadata_cache.items():
        if card_hash in meta_map:
            cached_item = meta_map[card_hash]
            return {
                "id": card_hash,
                "question": cached_item.get("question") or "Untitled Flashcard",
                "answer": cached_item.get("answer") or "*Card stored on Mobile Device*",
                "created_at": cached_item.get("created_at"),
                "tags": cached_item.get("tags") or [],
                "source_pdf": cached_item.get("source_pdf") or "Mobile Storage",
                "pdf_page": cached_item.get("pdf_page") or 0,
                "attachments": cached_item.get("attachments") or []
            }

    raise HTTPException(status_code=404, detail="Flashcard not found")

@app.get("/api/cards/{card_hash}/metadata")
def get_card_metadata(card_hash: str):
    """Extracts and returns the raw metadata.json from inside the .flash zip."""
    import zipfile
    import json
    file_path = settings.storage_path / f"{card_hash}.flash"
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="Flashcard not found")
        
    try:
        with zipfile.ZipFile(file_path, "r") as zip_file:
            metadata_str = zip_file.read("metadata.json").decode("utf-8")
            metadata = json.loads(metadata_str)
            metadata["id"] = card_hash
            return metadata
    except Exception as e:
        logger.error(f"Failed to read metadata for {card_hash}: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/cards/{card_hash}/assets/{filename}")
def get_card_asset(card_hash: str, filename: str):
    """Serves a static image/attachment from inside the flashcard zip."""
    import zipfile
    file_path = settings.storage_path / f"{card_hash}.flash"
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="Flashcard not found")
        
    try:
        with zipfile.ZipFile(file_path, "r") as zip_file:
            asset_path = f"assets/{filename}"
            if asset_path not in zip_file.namelist():
                raise HTTPException(status_code=404, detail=f"Asset {filename} not found inside flashcard")
                
            content_type = "image/png"
            if filename.lower().endswith((".jpg", ".jpeg")):
                content_type = "image/jpeg"
            elif filename.lower().endswith(".gif"):
                content_type = "image/gif"
            elif filename.lower().endswith(".svg"):
                content_type = "image/svg+xml"
                
            data = zip_file.read(asset_path)
            return Response(content=data, media_type=content_type)
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to extract asset {filename} from {card_hash}: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app.main:app", host=settings.HOST, port=settings.PORT, reload=True)
