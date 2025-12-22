"""
PhotoShare Web Client - FastAPI backend with WebSocket for real-time updates.
"""

import asyncio
import json
import os
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Request
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from config import Config
from sync import PhotoSyncClient

app = FastAPI(title="PhotoShare Client", version="1.0.0")

# Templates
templates_dir = Path(__file__).parent / "templates"
templates = Jinja2Templates(directory=str(templates_dir))

# Static files
static_dir = Path(__file__).parent / "static"
if static_dir.exists():
    app.mount("/static", StaticFiles(directory=str(static_dir)), name="static")

# WebSocket connection manager
class ConnectionManager:
    def __init__(self):
        self.active_connections: list[WebSocket] = []
    
    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)
    
    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)
    
    async def broadcast(self, message: dict):
        for connection in self.active_connections:
            try:
                await connection.send_json(message)
            except:
                pass

manager = ConnectionManager()

# Sync state
class SyncState:
    def __init__(self):
        self.is_syncing = False
        self.current_photo = 0
        self.total_photos = 0
        self.current_filename = ""
        self.downloaded_count = 0
        self.failed_count = 0
        self.bytes_downloaded = 0
        self.start_time: Optional[datetime] = None
        self.last_sync_time: Optional[datetime] = None
        self.error_message: Optional[str] = None

sync_state = SyncState()


@app.get("/", response_class=HTMLResponse)
async def home(request: Request):
    """Serve the main web interface."""
    return templates.TemplateResponse("index.html", {
        "request": request,
        "server_url": Config.SERVER_URL,
        "download_dir": str(Config.DOWNLOAD_DIR),
    })


@app.get("/api/config")
async def get_config():
    """Get current configuration."""
    return {
        "server_url": Config.SERVER_URL,
        "download_dir": str(Config.DOWNLOAD_DIR),
        "poll_interval_hours": Config.POLL_INTERVAL_HOURS,
        "last_sync_timestamp": _get_last_sync_timestamp(),
    }


@app.post("/api/config")
async def update_config(request: Request):
    """Update configuration."""
    data = await request.json()
    
    if "download_dir" in data:
        new_dir = Path(data["download_dir"])
        if not new_dir.exists():
            try:
                new_dir.mkdir(parents=True, exist_ok=True)
            except Exception as e:
                return JSONResponse(
                    {"error": f"Cannot create directory: {e}"},
                    status_code=400
                )
        Config.DOWNLOAD_DIR = new_dir
    
    if "server_url" in data:
        Config.SERVER_URL = data["server_url"]
    
    return {"status": "ok", "config": await get_config()}


@app.get("/api/stats")
async def get_stats():
    """Get sync statistics."""
    download_dir = Config.DOWNLOAD_DIR
    
    # Count files in download directory
    file_count = 0
    total_size = 0
    file_types = {}
    
    if download_dir.exists():
        for f in download_dir.iterdir():
            if f.is_file():
                file_count += 1
                size = f.stat().st_size
                total_size += size
                ext = f.suffix.lower()
                file_types[ext] = file_types.get(ext, 0) + 1
    
    return {
        "file_count": file_count,
        "total_size_bytes": total_size,
        "total_size_human": _format_bytes(total_size),
        "file_types": file_types,
        "download_dir": str(download_dir),
        "last_sync": sync_state.last_sync_time.isoformat() if sync_state.last_sync_time else None,
        "is_syncing": sync_state.is_syncing,
    }


@app.get("/api/status")
async def get_status():
    """Get current sync status."""
    return {
        "is_syncing": sync_state.is_syncing,
        "current_photo": sync_state.current_photo,
        "total_photos": sync_state.total_photos,
        "current_filename": sync_state.current_filename,
        "downloaded_count": sync_state.downloaded_count,
        "failed_count": sync_state.failed_count,
        "bytes_downloaded": sync_state.bytes_downloaded,
        "bytes_downloaded_human": _format_bytes(sync_state.bytes_downloaded),
        "progress_percent": (sync_state.current_photo / sync_state.total_photos * 100) if sync_state.total_photos > 0 else 0,
        "error_message": sync_state.error_message,
    }


@app.post("/api/sync")
async def start_sync(request: Request):
    """Start a sync operation."""
    if sync_state.is_syncing:
        return JSONResponse(
            {"error": "Sync already in progress"},
            status_code=400
        )
    
    data = await request.json() if request.headers.get("content-type") == "application/json" else {}
    since_date = data.get("since_date")
    
    # Convert date string to timestamp
    since_timestamp = None
    if since_date:
        try:
            dt = datetime.fromisoformat(since_date.replace("Z", "+00:00"))
            since_timestamp = dt.timestamp()
        except ValueError:
            return JSONResponse(
                {"error": "Invalid date format"},
                status_code=400
            )
    
    # Start sync in background
    asyncio.create_task(_run_sync(since_timestamp))
    
    return {"status": "started"}


@app.post("/api/sync/cancel")
async def cancel_sync():
    """Cancel current sync operation."""
    if not sync_state.is_syncing:
        return {"status": "not_running"}
    
    sync_state.is_syncing = False
    await manager.broadcast({
        "type": "sync_cancelled",
        "message": "Sync cancelled by user"
    })
    
    return {"status": "cancelled"}


@app.get("/api/health")
async def health_check():
    """Check if server is reachable."""
    try:
        with PhotoSyncClient() as client:
            is_healthy = client.check_health()
            return {
                "server_healthy": is_healthy,
                "server_url": Config.SERVER_URL
            }
    except Exception as e:
        return {
            "server_healthy": False,
            "server_url": Config.SERVER_URL,
            "error": str(e)
        }


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket endpoint for real-time updates."""
    await manager.connect(websocket)
    try:
        # Send initial status
        await websocket.send_json({
            "type": "status",
            "data": await get_status()
        })
        
        # Keep connection alive and handle incoming messages
        while True:
            try:
                data = await asyncio.wait_for(websocket.receive_text(), timeout=30)
                # Handle ping/pong
                if data == "ping":
                    await websocket.send_text("pong")
            except asyncio.TimeoutError:
                # Send heartbeat
                await websocket.send_json({"type": "heartbeat"})
    except WebSocketDisconnect:
        manager.disconnect(websocket)


async def _run_sync(since_timestamp: Optional[float] = None):
    """Run sync operation with progress updates."""
    global sync_state
    
    sync_state.is_syncing = True
    sync_state.current_photo = 0
    sync_state.total_photos = 0
    sync_state.current_filename = ""
    sync_state.downloaded_count = 0
    sync_state.failed_count = 0
    sync_state.bytes_downloaded = 0
    sync_state.start_time = datetime.now()
    sync_state.error_message = None
    
    await manager.broadcast({
        "type": "sync_started",
        "timestamp": sync_state.start_time.isoformat()
    })
    
    try:
        with PhotoSyncClient() as client:
            # Check health first
            if not client.check_health():
                sync_state.error_message = "Server health check failed"
                await manager.broadcast({
                    "type": "sync_error",
                    "message": sync_state.error_message
                })
                return
            
            # Get photos list
            await manager.broadcast({
                "type": "status_update",
                "message": "Fetching photo list..."
            })
            
            # Use provided timestamp or last sync time
            effective_since = since_timestamp or client.get_last_sync_time()
            
            # Log what date we're using
            if effective_since:
                from datetime import datetime as dt
                since_str = dt.fromtimestamp(effective_since).isoformat()
                await manager.broadcast({
                    "type": "status_update",
                    "message": f"Fetching photos since {since_str}"
                })
            else:
                await manager.broadcast({
                    "type": "status_update", 
                    "message": "Fetching ALL photos (no date filter)"
                })
            
            try:
                photos = client.list_photos(since=effective_since)
            except Exception as e:
                sync_state.error_message = f"Failed to list photos: {e}"
                await manager.broadcast({
                    "type": "sync_error",
                    "message": sync_state.error_message
                })
                return
            
            sync_state.total_photos = len(photos)
            
            await manager.broadcast({
                "type": "photos_found",
                "count": sync_state.total_photos
            })
            
            if not photos:
                await manager.broadcast({
                    "type": "sync_complete",
                    "downloaded": 0,
                    "failed": 0,
                    "message": "No new photos to download"
                })
                sync_state.last_sync_time = datetime.now()
                return
            
            # Download photos one by one
            sync_start_time = datetime.now().timestamp()
            
            for i, photo in enumerate(photos):
                if not sync_state.is_syncing:
                    break
                
                sync_state.current_photo = i + 1
                photo_id = photo["id"]
                
                # Estimate filename
                creation_date = photo.get("creationDate", "")
                if creation_date:
                    try:
                        dt = datetime.fromisoformat(creation_date.replace("Z", "+00:00"))
                        sync_state.current_filename = dt.strftime("%Y%m%d_%H%M%S")
                    except:
                        sync_state.current_filename = photo_id[:20]
                else:
                    sync_state.current_filename = photo_id[:20]
                
                await manager.broadcast({
                    "type": "downloading",
                    "current": sync_state.current_photo,
                    "total": sync_state.total_photos,
                    "filename": sync_state.current_filename,
                    "photo_id": photo_id,
                    "media_type": photo.get("mediaType", "unknown"),
                })
                
                # Download the photo
                result = client.download_photo(photo_id, photo)
                
                if result == "skipped":
                    # Already downloaded, skip
                    await manager.broadcast({
                        "type": "skipped",
                        "current": sync_state.current_photo,
                        "total": sync_state.total_photos,
                        "photo_id": photo_id,
                    })
                elif result:
                    sync_state.downloaded_count += 1
                    file_size = result.stat().st_size if result.exists() else 0
                    sync_state.bytes_downloaded += file_size
                    
                    await manager.broadcast({
                        "type": "downloaded",
                        "current": sync_state.current_photo,
                        "total": sync_state.total_photos,
                        "filename": result.name,
                        "size": file_size,
                        "size_human": _format_bytes(file_size),
                    })
                else:
                    sync_state.failed_count += 1
                    await manager.broadcast({
                        "type": "download_failed",
                        "current": sync_state.current_photo,
                        "total": sync_state.total_photos,
                        "photo_id": photo_id,
                    })
            
            # Save sync time
            client.save_sync_time(sync_start_time)
            sync_state.last_sync_time = datetime.now()
            
            await manager.broadcast({
                "type": "sync_complete",
                "downloaded": sync_state.downloaded_count,
                "failed": sync_state.failed_count,
                "bytes_total": sync_state.bytes_downloaded,
                "bytes_total_human": _format_bytes(sync_state.bytes_downloaded),
                "duration_seconds": (datetime.now() - sync_state.start_time).total_seconds(),
            })
            
    except Exception as e:
        sync_state.error_message = str(e)
        await manager.broadcast({
            "type": "sync_error",
            "message": sync_state.error_message
        })
    finally:
        sync_state.is_syncing = False


def _get_last_sync_timestamp() -> Optional[float]:
    """Get last sync timestamp from state file."""
    if not Config.STATE_FILE.exists():
        return None
    try:
        state = json.loads(Config.STATE_FILE.read_text())
        return state.get("last_sync_timestamp")
    except:
        return None


def _format_bytes(size: int) -> str:
    """Format bytes to human readable string."""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if size < 1024:
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} PB"


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)

