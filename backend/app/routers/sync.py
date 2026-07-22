import zipfile
import json
import logging
import shutil
from pathlib import Path
from fastapi import APIRouter, HTTPException, BackgroundTasks, File, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel
from typing import Dict, List, Set
from app.config import settings

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/sync", tags=["sync"])

from typing import Dict, List, Set, Optional

# In-memory storage for device library states, sync queues, prune queues, and metadata cache
device_libraries: Dict[str, Set[str]] = {}
device_sync_queues: Dict[str, List[str]] = {}
device_sync_prunes: Dict[str, List[str]] = {}
device_metadata_cache: Dict[str, Dict[str, dict]] = {}

class CardMetadataItem(BaseModel):
    id: str
    question: str
    answer: Optional[str] = ""
    created_at: Optional[str] = None
    tags: Optional[List[str]] = None
    source_pdf: Optional[str] = None
    pdf_page: Optional[int] = 0
    attachments: Optional[List[str]] = None

class LibraryStateRequest(BaseModel):
    card_hashes: Optional[List[str]] = None
    cards_metadata: Optional[List[CardMetadataItem]] = None

class QueueSyncRequest(BaseModel):
    card_hashes: List[str]

def get_pc_library() -> List[dict]:
    """Scans storage folder and extracts metadata from all .flash zip cards."""
    cards = []
    storage_path = settings.storage_path
    
    for path in storage_path.glob("*.flash"):
        try:
            with zipfile.ZipFile(path, "r") as zip_file:
                metadata_str = zip_file.read("metadata.json").decode("utf-8")
                metadata = json.loads(metadata_str)
                # Ensure id matches base filename just in case
                metadata["id"] = path.stem
                cards.append(metadata)
        except Exception as e:
            logger.warning(f"Failed to read flashcard zip {path.name}: {e}")
            
    # Sort by creation time descending
    cards.sort(key=lambda x: x.get("created_at", ""), reverse=True)
    return cards

@router.post("/device/{device_id}/library")
def update_device_library(device_id: str, req: LibraryStateRequest):
    """The mobile phone calls this to upload its current list of card hashes and metadata."""
    hashes = set()
    metadata_map = {}
    
    if req.cards_metadata:
        for item in req.cards_metadata:
            hashes.add(item.id)
            metadata_map[item.id] = item.dict()
    if req.card_hashes:
        for h in req.card_hashes:
            hashes.add(h)

    device_libraries[device_id] = hashes
    if metadata_map:
        if device_id not in device_metadata_cache:
            device_metadata_cache[device_id] = {}
        device_metadata_cache[device_id].update(metadata_map)
    
    logger.info(f"Updated library state for device {device_id} with {len(hashes)} cards.")
    
    # Initialize queue for this device if not exists
    if device_id not in device_sync_queues:
        device_sync_queues[device_id] = []
        
    from app.routers.pairing import notify_listeners
    notify_listeners()
        
    return {"status": "success", "count": len(hashes)}

@router.get("/device/{device_id}/compare")
def compare_libraries(device_id: str):
    """
    Returns side-by-side library states:
    PC cards (with sync status) and Phone cards.
    """
    pc_cards = get_pc_library()
    phone_hashes = device_libraries.get(device_id, set())
    phone_meta = device_metadata_cache.get(device_id, {})
    
    # Enrich PC cards with sync status
    enriched_pc_cards = []
    for card in pc_cards:
        card_hash = card["id"]
        is_synced = card_hash in phone_hashes
        
        enriched_pc_cards.append({
            **card,
            "sync_status": "synced" if is_synced else "only_pc"
        })
        
    # Also compile cards that are on the phone
    pc_hashes = {card["id"] for card in pc_cards}
    only_phone_hashes = phone_hashes - pc_hashes
    
    phone_cards = []
    # For common cards, use PC metadata
    for card in pc_cards:
        card_hash = card["id"]
        if card_hash in phone_hashes:
            phone_cards.append({
                "id": card_hash,
                "question": card["question"],
                "created_at": card.get("created_at"),
                "sync_status": "synced",
                "source_pdf": card.get("source_pdf"),
                "tags": card.get("tags", []),
                "pdf_page": card.get("pdf_page")
            })
            
    # For items unique to phone (e.g. edited on phone or removed from PC)
    for p_hash in only_phone_hashes:
        cached_item = phone_meta.get(p_hash)
        if cached_item:
            phone_cards.append({
                "id": p_hash,
                "question": cached_item.get("question") or "Local Card on Phone",
                "created_at": cached_item.get("created_at"),
                "sync_status": "only_phone",
                "source_pdf": cached_item.get("source_pdf") or "Mobile Storage",
                "tags": cached_item.get("tags") or [],
                "pdf_page": cached_item.get("pdf_page") or 0
            })
        else:
            phone_cards.append({
                "id": p_hash,
                "question": "Local card on Phone",
                "created_at": None,
                "sync_status": "only_phone"
            })
        
    return {
        "pc_cards": enriched_pc_cards,
        "phone_cards": phone_cards
    }

@router.post("/device/{device_id}/queue")
def queue_cards_for_sync(device_id: str, req: QueueSyncRequest):
    """PC React UI calls this to queue specific card hashes for transfer to the phone."""
    if device_id not in device_sync_queues:
        device_sync_queues[device_id] = []
        
    # Filter to avoid duplicate queueing and ensure cards exist on PC
    storage_path = settings.storage_path
    queued_set = set(device_sync_queues[device_id])
    
    added_count = 0
    for card_hash in req.card_hashes:
        file_path = storage_path / f"{card_hash}.flash"
        if file_path.exists() and card_hash not in queued_set:
            device_sync_queues[device_id].append(card_hash)
            queued_set.add(card_hash)
            added_count += 1
            
    logger.info(f"Queued {added_count} cards for device {device_id}. Total queued: {len(device_sync_queues[device_id])}")
    return {"status": "success", "queued_count": len(device_sync_queues[device_id])}

@router.get("/device/{device_id}/pending")
def get_pending_syncs(device_id: str):
    """The mobile phone polls this to get its transfer queue and prune queue."""
    pending = device_sync_queues.get(device_id, [])
    prune = device_sync_prunes.get(device_id, [])
    return {"pending_hashes": pending, "prune_hashes": prune}

@router.get("/card/{card_hash}/download")
def download_card_file(card_hash: str):
    """The mobile phone requests download of a specific .flash ZIP archive."""
    file_path = settings.storage_path / f"{card_hash}.flash"
    
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="Card file not found")
        
    return FileResponse(
        path=str(file_path),
        media_type="application/zip",
        filename=f"{card_hash}.flash"
    )

import hashlib
from app.routers.pairing import notify_listeners

@router.post("/device/{device_id}/complete/{card_hash}")
def confirm_sync_complete(device_id: str, card_hash: str, checksum: str = None):
    """The mobile phone calls this to notify that it has successfully downloaded and saved the card."""
    # Check file integrity using SHA256 checksum if provided by phone
    file_path = settings.storage_path / f"{card_hash}.flash"
    if file_path.exists() and checksum:
        sha256 = hashlib.sha256()
        try:
            with open(file_path, "rb") as f:
                for byte_block in iter(lambda: f.read(4096), b""):
                    sha256.update(byte_block)
            server_checksum = sha256.hexdigest()
            if checksum != server_checksum:
                logger.error(f"Integrity check failed for {card_hash}: expected {server_checksum}, got {checksum}")
                raise HTTPException(status_code=400, detail="File integrity check failed: Checksum mismatch")
        except HTTPException:
            raise
        except Exception as err:
            logger.warning(f"Failed to calculate server checksum for card {card_hash}: {err}")
            
    # Remove from sync queue
    queue = device_sync_queues.get(device_id, [])
    if card_hash in queue:
        queue.remove(card_hash)
        
    # Mark as present in phone library
    if device_id not in device_libraries:
        device_libraries[device_id] = set()
    device_libraries[device_id].add(card_hash)
    
    logger.info(f"Device {device_id} successfully synced card {card_hash}")
    
    # Notify React UI long-polling watch sessions of sync completion
    notify_listeners()
    
    return {"status": "success"}

@router.post("/device/{device_id}/upload_flash")
async def upload_flash_file(device_id: str, file: UploadFile = File(...)):
    """Receives a .flash zip file uploaded from mobile phone and stores it on PC."""
    try:
        filename = file.filename
        if filename.endswith(".flash"):
            card_id = filename[:-6]
        else:
            card_id = filename
            
        target_path = settings.storage_path / f"{card_id}.flash"
        
        with open(target_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
            
        logger.info(f"Uploaded flashcard {card_id}.flash from device {device_id}")
        
        if device_id not in device_libraries:
            device_libraries[device_id] = set()
        device_libraries[device_id].add(card_id)
        
        notify_listeners()
        return {"status": "success", "card_id": card_id}
    except Exception as e:
        logger.error(f"Failed to upload flashcard from phone: {e}")
        raise HTTPException(status_code=500, detail=str(e))
