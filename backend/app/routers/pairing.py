import socket
import threading
import json
import logging
import uuid
import io
import qrcode
from fastapi import APIRouter, HTTPException, Depends, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import Dict, List
from app.config import settings

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/pairing", tags=["pairing"])

# Global session states
class DeviceSession(BaseModel):
    device_id: str
    device_name: str
    ip: str
    paired_at: str

# In-memory storage for active pairing code and paired devices
class PairingState:
    def __init__(self):
        self.pairing_code: str = str(uuid.uuid4())[:8]  # Compact 8 character code
        self.paired_devices: Dict[str, DeviceSession] = {}
        self.udp_thread: threading.Thread = None
        self.stop_udp: threading.Event = threading.Event()
        self.listeners = []

pairing_state = PairingState()

def notify_listeners():
    """Trigger all active HTTP long-polling watch sessions to wake up."""
    for event in pairing_state.listeners:
        try:
            event.set()
        except Exception:
            pass
    pairing_state.listeners.clear()

class PairRequest(BaseModel):
    pairing_code: str
    device_id: str
    device_name: str
    client_ip: str

def get_local_ips() -> List[str]:
    """Retrieves all local IPv4 addresses (excluding loopback)."""
    ips = []
    # Method 1: Check hostname-resolved IPs
    try:
        hostname = socket.gethostname()
        for ip in socket.gethostbyname_ex(hostname)[2]:
            if not ip.startswith("127."):
                ips.append(ip)
    except Exception:
        pass
        
    # Method 2: Create a dummy connection to find default gateway interface
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        primary_ip = s.getsockname()[0]
        s.close()
        if primary_ip not in ips:
            ips.append(primary_ip)
    except Exception:
        pass
        
    # Fallback to local loopback if empty
    if not ips:
        ips = ["127.0.0.1"]
    return list(set(ips))

@router.get("/info")
def get_pairing_info():
    """Returns pairing code, port, and NIC IPs for the PC UI to render QR code."""
    # Rotate pairing code on request to keep it fresh
    pairing_state.pairing_code = str(uuid.uuid4())[:8]
    
    ips = get_local_ips()
    return {
        "pairing_code": pairing_state.pairing_code,
        "port": settings.PORT,
        "ips": ips
    }

@router.get("/qr")
def get_pairing_qr():
    """Generates a QR code image containing the current pairing details."""
    pairing_data = {
        "pairing_code": pairing_state.pairing_code,
        "port": settings.PORT,
        "ips": get_local_ips()
    }
    qr_str = json.dumps(pairing_data)
    
    # Generate QR Code
    qr = qrcode.QRCode(version=1, box_size=10, border=4)
    qr.add_data(qr_str)
    qr.make(fit=True)
    
    img = qr.make_image(fill_color="black", back_color="white")
    
    # Save to BytesIO buffer
    img_byte_arr = io.BytesIO()
    img.save(img_byte_arr, format='PNG')
    img_byte_arr.seek(0)
    
    return StreamingResponse(img_byte_arr, media_type="image/png")

@router.post("/pair")
def pair_device(req: PairRequest, request: Request):
    """Pair via HTTP POST fallback if UDP broadcast does not work or as final handshake."""
    if req.pairing_code != pairing_state.pairing_code:
        raise HTTPException(status_code=400, detail="Invalid pairing code")
        
    client_ip = request.client.host if request.client else req.client_ip
    if client_ip == "127.0.0.1" and req.client_ip != "127.0.0.1":
        client_ip = req.client_ip

    import datetime
    session = DeviceSession(
        device_id=req.device_id,
        device_name=req.device_name,
        ip=client_ip,
        paired_at=datetime.datetime.utcnow().isoformat() + "Z"
    )
    pairing_state.paired_devices[req.device_id] = session
    logger.info(f"Paired device {req.device_name} ({req.device_id}) at {client_ip}")
    notify_listeners()
    return {"status": "success", "device_id": req.device_id}

@router.get("/devices")
def get_paired_devices():
    """List currently connected/paired mobile devices."""
    return list(pairing_state.paired_devices.values())

@router.post("/disconnect/{device_id}")
def disconnect_device(device_id: str):
    """The mobile phone calls this to disconnect itself from the PC."""
    if device_id in pairing_state.paired_devices:
        disconnected = pairing_state.paired_devices.pop(device_id)
        logger.info(f"Disconnected device: {disconnected.device_name} ({device_id})")
        notify_listeners()
    return {"status": "success"}

import asyncio

@router.get("/watch")
async def watch_devices(timeout: int = 25):
    """Long polling watcher endpoint to wait for pairing/sync changes."""
    event = asyncio.Event()
    pairing_state.listeners.append(event)
    try:
        await asyncio.wait_for(event.wait(), timeout=timeout)
    except asyncio.TimeoutError:
        pass
    finally:
        if event in pairing_state.listeners:
            pairing_state.listeners.remove(event)
    return list(pairing_state.paired_devices.values())

# UDP Broadcast Discovery listener removed in favor of direct concurrent TCP scans
