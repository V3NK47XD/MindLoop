import socket
import threading
import json
import logging
import uuid
import io
import time
import qrcode
from fastapi import APIRouter, HTTPException, Depends
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
    last_seen: float = 0.0

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
def pair_device(req: PairRequest):
    """Pair via HTTP POST fallback if UDP broadcast does not work or as final handshake."""
    if req.pairing_code != pairing_state.pairing_code:
        raise HTTPException(status_code=400, detail="Invalid pairing code")
        
    import datetime
    session = DeviceSession(
        device_id=req.device_id,
        device_name=req.device_name,
        ip=req.client_ip,
        paired_at=datetime.datetime.utcnow().isoformat() + "Z",
        last_seen=time.time()
    )
    pairing_state.paired_devices[req.device_id] = session
    logger.info(f"Paired device {req.device_name} ({req.device_id}) at {req.client_ip}")
    notify_listeners()
    return {"status": "success", "device_id": req.device_id}

@router.get("/devices")
def get_paired_devices():
    """List currently connected/paired mobile devices."""
    return list(pairing_state.paired_devices.values())

class HeartbeatRequest(BaseModel):
    device_name: str
    client_ip: str

@router.post("/heartbeat/{device_id}")
def device_heartbeat(device_id: str, req: HeartbeatRequest):
    now = time.time()
    is_new = False
    
    if device_id not in pairing_state.paired_devices:
        is_new = True
        import datetime
        session = DeviceSession(
            device_id=device_id,
            device_name=req.device_name,
            ip=req.client_ip,
            paired_at=datetime.datetime.utcnow().isoformat() + "Z",
            last_seen=now
        )
        pairing_state.paired_devices[device_id] = session
        logger.info(f"Reconnected device {req.device_name} ({device_id}) via heartbeat.")
    else:
        session = pairing_state.paired_devices[device_id]
        session.last_seen = now
        # Keep name and IP fresh
        session.ip = req.client_ip
        session.device_name = req.device_name
        
    if is_new:
        notify_listeners()
        
    return {"status": "success", "device_id": device_id}

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

# UDP Listener for Broadcast Discovery
def start_udp_broadcast_listener():
    """Runs a UDP listener on port 6769 in a background thread."""
    def listen_loop():
        # Bind socket
        udp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        udp_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        
        try:
            udp_sock.bind(("0.0.0.0", settings.PORT))
            udp_sock.settimeout(1.0)
            logger.info(f"UDP discovery listener bound to port {settings.PORT}")
        except Exception as e:
            logger.error(f"Failed to bind UDP socket: {e}")
            return
            
        while not pairing_state.stop_udp.is_set():
            try:
                data, addr = udp_sock.recvfrom(2048)
                payload = json.loads(data.decode("utf-8"))
                
                # Check message fields
                action = payload.get("action")
                received_code = payload.get("pairing_code")
                
                if action == "discover" and received_code == pairing_state.pairing_code:
                    logger.info(f"UDP Discovery request matched code from {addr}")
                    # Respond to sender with server info
                    response_payload = {
                        "action": "discover_reply",
                        "server_port": settings.PORT,
                        "status": "ok"
                    }
                    udp_sock.sendto(json.dumps(response_payload).encode("utf-8"), addr)
            except socket.timeout:
                continue
            except Exception as e:
                logger.debug(f"UDP listener parse error: {e}")
                continue
                
        udp_sock.close()
        logger.info("UDP discovery listener stopped.")

    pairing_state.stop_udp.clear()
    pairing_state.udp_thread = threading.Thread(target=listen_loop, daemon=True)
    pairing_state.udp_thread.start()

    # Heartbeat Pruner Loop
    def prune_loop():
        logger.info("Heartbeat pruner thread started.")
        while not pairing_state.stop_udp.is_set():
            # Sleep in small increments to respond to stop signals quickly
            for _ in range(30):
                if pairing_state.stop_udp.is_set():
                    break
                time.sleep(0.1)
            
            now = time.time()
            to_delete = []
            for dev_id, session in list(pairing_state.paired_devices.items()):
                if session.last_seen > 0 and (now - session.last_seen) > 8.0:
                    to_delete.append(dev_id)
            if to_delete:
                for dev_id in to_delete:
                    pairing_state.paired_devices.pop(dev_id, None)
                    logger.info(f"Heartbeat timeout. Pruned inactive device: {dev_id}")
                notify_listeners()
        logger.info("Heartbeat pruner thread stopped.")

    threading.Thread(target=prune_loop, daemon=True).start()

def stop_udp_broadcast_listener():
    if pairing_state.udp_thread:
        pairing_state.stop_udp.set()
        pairing_state.udp_thread.join(timeout=2.0)
        logger.info("UDP listener shutdown requested.")
