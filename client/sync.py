"""Photo synchronization logic for PhotoShare client."""

import json
import logging
from datetime import datetime
from pathlib import Path
from typing import List, Optional
from urllib.parse import urlparse

import httpx

from auth import generate_auth_headers
from config import Config

logger = logging.getLogger(__name__)


class PhotoSyncClient:
    """Client for synchronizing photos from PhotoShare server."""
    
    def __init__(self, config: Config = Config):
        self.config = config
        self.config.ensure_directories()
        self._client: Optional[httpx.Client] = None
    
    @property
    def client(self) -> httpx.Client:
        """Lazy-initialize the HTTP client."""
        if self._client is None:
            self._client = httpx.Client(
                base_url=self.config.SERVER_URL,
                timeout=self.config.REQUEST_TIMEOUT,
            )
        return self._client
    
    def close(self) -> None:
        """Close the HTTP client."""
        if self._client is not None:
            self._client.close()
            self._client = None
    
    def __enter__(self):
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()
    
    def _make_request(
        self,
        method: str,
        path: str,
        **kwargs,
    ) -> httpx.Response:
        """Make an authenticated request to the server."""
        # Extract just the path portion (without query string) for signature
        # The server's HMAC middleware uses request.url.path which excludes query params
        sign_path = path.split("?")[0]
        headers = generate_auth_headers(method, sign_path, self.config.SHARED_SECRET)
        
        if "headers" in kwargs:
            headers.update(kwargs.pop("headers"))
        
        response = self.client.request(method, path, headers=headers, **kwargs)
        response.raise_for_status()
        return response
    
    def get_last_sync_time(self) -> Optional[float]:
        """Get the timestamp of the last successful sync."""
        if not self.config.STATE_FILE.exists():
            return None
        
        try:
            state = json.loads(self.config.STATE_FILE.read_text())
            return state.get("last_sync_timestamp")
        except (json.JSONDecodeError, IOError) as e:
            logger.warning(f"Could not read sync state: {e}")
            return None
    
    def save_sync_time(self, timestamp: float) -> None:
        """Save the timestamp of the last successful sync."""
        state = {"last_sync_timestamp": timestamp}
        self.config.STATE_FILE.write_text(json.dumps(state))
    
    def list_photos(self, since: Optional[float] = None) -> List[dict]:
        """
        List photos from the server.
        
        Args:
            since: Only return photos created after this Unix timestamp
        
        Returns:
            List of photo metadata dictionaries
        """
        path = "/photos"
        if since is not None:
            path = f"/photos?since={since}"
        
        response = self._make_request("GET", path)
        data = response.json()
        
        logger.info(f"Found {data['count']} photos")
        return data["photos"]
    
    def download_photo(self, photo_id: str, photo_metadata: dict) -> Optional[Path]:
        """
        Download a single photo.
        
        Args:
            photo_id: The photo's unique identifier
            photo_metadata: Photo metadata from list_photos
        
        Returns:
            Path to the downloaded file, or None if download failed
        """
        # Determine if this is a Live Photo
        is_live_photo = "livePhoto" in photo_metadata.get("mediaSubtypes", [])
        
        if is_live_photo:
            return self._download_live_photo(photo_id, photo_metadata)
        else:
            return self._download_regular_photo(photo_id, photo_metadata)
    
    def _download_regular_photo(self, photo_id: str, photo_metadata: dict) -> Optional[Path]:
        """Download a regular photo or video."""
        from urllib.parse import quote
        encoded_id = quote(photo_id, safe='')
        path = f"/photos/{encoded_id}/download"
        
        try:
            response = self._make_request("GET", path)
            
            # Get filename from headers or generate one
            filename = response.headers.get("X-Original-Filename")
            if not filename:
                # Generate filename from creation date
                creation_date = photo_metadata.get("creationDate", "")
                if creation_date:
                    dt = datetime.fromisoformat(creation_date.replace("Z", "+00:00"))
                    filename = dt.strftime("%Y%m%d_%H%M%S")
                else:
                    filename = photo_id.replace("/", "_")
                
                # Add extension based on media type
                media_type = response.headers.get("X-Media-Type", "image")
                ext = ".mp4" if media_type == "video" else ".jpg"
                filename += ext
            
            # Sanitize filename
            filename = self._sanitize_filename(filename)
            
            # Save to disk
            output_path = self.config.DOWNLOAD_DIR / filename
            
            # Handle duplicate filenames
            counter = 1
            base_path = output_path
            while output_path.exists():
                stem = base_path.stem
                suffix = base_path.suffix
                output_path = base_path.with_name(f"{stem}_{counter}{suffix}")
                counter += 1
            
            output_path.write_bytes(response.content)
            logger.info(f"Downloaded: {output_path}")
            
            return output_path
            
        except httpx.HTTPError as e:
            logger.error(f"Failed to download photo {photo_id}: {e}")
            return None
    
    def _download_live_photo(self, photo_id: str, photo_metadata: dict) -> Optional[Path]:
        """Download a Live Photo (photo + video components)."""
        from urllib.parse import quote
        encoded_id = quote(photo_id, safe='')
        path = f"/photos/{encoded_id}/livephoto"
        
        try:
            response = self._make_request("GET", path)
            
            # Parse multipart response
            content_type = response.headers.get("content-type", "")
            if "boundary=" not in content_type:
                logger.error("Invalid Live Photo response: no boundary")
                return None
            
            boundary = content_type.split("boundary=")[1].strip()
            
            # Simple multipart parser
            parts = response.content.split(f"--{boundary}".encode())
            
            saved_files = []
            for part in parts:
                if b"Content-Disposition" not in part:
                    continue
                
                # Extract filename
                header_end = part.find(b"\r\n\r\n")
                if header_end == -1:
                    continue
                
                headers = part[:header_end].decode("utf-8", errors="ignore")
                content = part[header_end + 4:]
                
                # Remove trailing \r\n
                if content.endswith(b"\r\n"):
                    content = content[:-2]
                
                # Extract filename from Content-Disposition
                filename = None
                for line in headers.split("\r\n"):
                    if "filename=" in line:
                        filename = line.split('filename="')[1].split('"')[0]
                        break
                
                if filename and content:
                    filename = self._sanitize_filename(filename)
                    output_path = self.config.DOWNLOAD_DIR / filename
                    
                    # Handle duplicates
                    counter = 1
                    base_path = output_path
                    while output_path.exists():
                        stem = base_path.stem
                        suffix = base_path.suffix
                        output_path = base_path.with_name(f"{stem}_{counter}{suffix}")
                        counter += 1
                    
                    output_path.write_bytes(content)
                    saved_files.append(output_path)
                    logger.info(f"Downloaded Live Photo component: {output_path}")
            
            return saved_files[0] if saved_files else None
            
        except httpx.HTTPError as e:
            logger.error(f"Failed to download Live Photo {photo_id}: {e}")
            return None
    
    def _sanitize_filename(self, filename: str) -> str:
        """Sanitize a filename for safe filesystem use."""
        # Remove or replace problematic characters
        invalid_chars = '<>:"/\\|?*'
        for char in invalid_chars:
            filename = filename.replace(char, "_")
        return filename
    
    def sync(self) -> int:
        """
        Perform a full sync operation.
        
        Returns:
            Number of photos downloaded
        """
        logger.info("Starting photo sync...")
        
        # Get last sync time
        last_sync = self.get_last_sync_time()
        if last_sync:
            logger.info(f"Syncing photos since {datetime.fromtimestamp(last_sync)}")
        else:
            logger.info("First sync - fetching all photos")
        
        # Record current time for next sync
        sync_start_time = datetime.now().timestamp()
        
        # List new photos
        try:
            photos = self.list_photos(since=last_sync)
        except httpx.HTTPError as e:
            logger.error(f"Failed to list photos: {e}")
            return 0
        
        if not photos:
            logger.info("No new photos to download")
            self.save_sync_time(sync_start_time)
            return 0
        
        # Download each photo
        downloaded = 0
        for photo in photos:
            photo_id = photo["id"]
            logger.info(f"Downloading photo {downloaded + 1}/{len(photos)}: {photo_id}")
            
            result = self.download_photo(photo_id, photo)
            if result:
                downloaded += 1
        
        # Save sync time
        self.save_sync_time(sync_start_time)
        
        logger.info(f"Sync complete: {downloaded}/{len(photos)} photos downloaded")
        return downloaded
    
    def check_health(self) -> bool:
        """Check if the server is healthy."""
        try:
            response = self.client.get("/health")
            return response.status_code == 200
        except httpx.HTTPError:
            return False

