import os
import shutil
import uuid
import logging
from pathlib import Path
from contextlib import asynccontextmanager
from fastapi import FastAPI, UploadFile, File, HTTPException, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.config import settings
from app.routers import pairing, sync
from app.services.pdf_service import extract_pdf_content
from app.services.generator import generate_flashcards_from_pdf, get_pc_library

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
    model: str = Form(None)
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
            storage_dir=settings.storage_path
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

@app.get("/api/cards")
def list_cards():
    """List all flashcards stored on the PC."""
    try:
        return get_pc_library()
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

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app.main:app", host=settings.HOST, port=settings.PORT, reload=True)
