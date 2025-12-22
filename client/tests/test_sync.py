"""Unit tests for the sync module."""

import json
import tempfile
from datetime import datetime
from pathlib import Path
from unittest.mock import MagicMock, patch

import httpx
import pytest

from sync import PhotoSyncClient


class TestPhotoSyncClient:
    """Tests for PhotoSyncClient class."""
    
    @pytest.fixture
    def temp_dir(self):
        """Create a temporary directory for tests."""
        with tempfile.TemporaryDirectory() as tmpdir:
            yield Path(tmpdir)
    
    @pytest.fixture
    def mock_config(self, temp_dir):
        """Create a mock config for testing."""
        config = MagicMock()
        config.SERVER_URL = "http://localhost:8080"
        config.SHARED_SECRET = "test-secret"
        config.DOWNLOAD_DIR = temp_dir / "downloads"
        config.STATE_FILE = temp_dir / ".sync_state"
        config.REQUEST_TIMEOUT = 30
        config.ensure_directories = MagicMock()
        return config
    
    @pytest.fixture
    def client(self, mock_config):
        """Create a PhotoSyncClient with mock config."""
        client = PhotoSyncClient(mock_config)
        yield client
        client.close()
    
    # MARK: - Initialization Tests
    
    def test_init_ensures_directories(self, mock_config):
        """Should call ensure_directories on init."""
        client = PhotoSyncClient(mock_config)
        mock_config.ensure_directories.assert_called_once()
        client.close()
    
    def test_context_manager(self, mock_config):
        """Should work as a context manager."""
        with PhotoSyncClient(mock_config) as client:
            assert client is not None
    
    # MARK: - State Management Tests
    
    def test_get_last_sync_time_no_file(self, client, mock_config):
        """Should return None if state file doesn't exist."""
        assert client.get_last_sync_time() is None
    
    def test_get_last_sync_time_with_file(self, client, mock_config):
        """Should return timestamp from state file."""
        mock_config.STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
        mock_config.STATE_FILE.write_text('{"last_sync_timestamp": 1700000000}')
        
        assert client.get_last_sync_time() == 1700000000
    
    def test_get_last_sync_time_invalid_json(self, client, mock_config):
        """Should return None if state file has invalid JSON."""
        mock_config.STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
        mock_config.STATE_FILE.write_text('not valid json')
        
        assert client.get_last_sync_time() is None
    
    def test_save_sync_time(self, client, mock_config):
        """Should save timestamp to state file."""
        mock_config.STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
        
        client.save_sync_time(1700000000)
        
        state = json.loads(mock_config.STATE_FILE.read_text())
        assert state["last_sync_timestamp"] == 1700000000
    
    # MARK: - Filename Sanitization Tests
    
    def test_sanitize_filename_removes_invalid_chars(self, client):
        """Should remove/replace invalid filename characters."""
        assert client._sanitize_filename('photo<>:"/\\|?*.jpg') == 'photo_________.jpg'
    
    def test_sanitize_filename_preserves_valid_chars(self, client):
        """Should preserve valid filename characters."""
        assert client._sanitize_filename('IMG_1234.heic') == 'IMG_1234.heic'
    
    # MARK: - Health Check Tests
    
    def test_check_health_success(self, client, mock_config):
        """Should return True when server returns 200."""
        mock_config.DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
        
        with patch('sync.httpx.Client') as mock_client_class:
            mock_http = MagicMock()
            mock_client_class.return_value = mock_http
            mock_response = MagicMock()
            mock_response.status_code = 200
            mock_http.get.return_value = mock_response
            
            # Force client to reinitialize
            client._client = None
            client._client = mock_http
            
            assert client.check_health() is True
    
    def test_check_health_failure(self, client, mock_config):
        """Should return False when server returns error."""
        mock_config.DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
        
        mock_http = MagicMock()
        mock_response = MagicMock()
        mock_response.status_code = 500
        mock_http.get.return_value = mock_response
        
        client._client = mock_http
        
        assert client.check_health() is False
    
    def test_check_health_connection_error(self, client, mock_config):
        """Should return False on connection error."""
        mock_config.DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
        
        mock_http = MagicMock()
        mock_http.get.side_effect = httpx.ConnectError("Connection refused")
        
        client._client = mock_http
        
        assert client.check_health() is False


class TestPhotoSyncClientIntegration:
    """Integration tests for PhotoSyncClient with mocked HTTP."""
    
    @pytest.fixture
    def temp_dir(self):
        """Create a temporary directory for tests."""
        with tempfile.TemporaryDirectory() as tmpdir:
            yield Path(tmpdir)
    
    @pytest.fixture
    def mock_config(self, temp_dir):
        """Create a mock config for testing."""
        config = MagicMock()
        config.SERVER_URL = "http://localhost:8080"
        config.SHARED_SECRET = "test-secret"
        config.DOWNLOAD_DIR = temp_dir / "downloads"
        config.STATE_FILE = temp_dir / ".sync_state"
        config.REQUEST_TIMEOUT = 30
        config.ensure_directories = MagicMock()
        return config
    
    def test_list_photos_parses_response(self, mock_config, temp_dir):
        """Should parse photo list response correctly."""
        mock_config.DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
        
        mock_response_data = {
            "count": 2,
            "photos": [
                {
                    "id": "photo1",
                    "creationDate": "2024-01-15T10:30:00Z",
                    "mediaType": "image",
                    "mediaSubtypes": [],
                },
                {
                    "id": "photo2",
                    "creationDate": "2024-01-16T10:30:00Z",
                    "mediaType": "video",
                    "mediaSubtypes": [],
                },
            ]
        }
        
        with PhotoSyncClient(mock_config) as client:
            with patch.object(client, '_make_request') as mock_request:
                mock_response = MagicMock()
                mock_response.json.return_value = mock_response_data
                mock_request.return_value = mock_response
                
                photos = client.list_photos()
                
                assert len(photos) == 2
                assert photos[0]["id"] == "photo1"
                assert photos[1]["id"] == "photo2"
    
    def test_list_photos_with_since_parameter(self, mock_config, temp_dir):
        """Should include since parameter in request path."""
        mock_config.DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
        
        with PhotoSyncClient(mock_config) as client:
            with patch.object(client, '_make_request') as mock_request:
                mock_response = MagicMock()
                mock_response.json.return_value = {"count": 0, "photos": []}
                mock_request.return_value = mock_response
                
                client.list_photos(since=1700000000)
                
                mock_request.assert_called_once()
                call_args = mock_request.call_args
                # Full path with query string is passed to _make_request
                assert "since=1700000000" in call_args[0][1]
                # But signature should only use path portion (handled inside _make_request)
    
    def test_download_photo_saves_file(self, mock_config, temp_dir):
        """Should save downloaded photo to disk."""
        mock_config.DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
        
        photo_content = b"fake image data"
        photo_metadata = {
            "id": "photo1",
            "creationDate": "2024-01-15T10:30:00Z",
            "mediaType": "image",
            "mediaSubtypes": [],
        }
        
        with PhotoSyncClient(mock_config) as client:
            with patch.object(client, '_make_request') as mock_request:
                mock_response = MagicMock()
                mock_response.headers = {
                    "X-Original-Filename": "IMG_1234.jpg",
                    "X-Media-Type": "image",
                }
                mock_response.content = photo_content
                mock_request.return_value = mock_response
                
                result = client.download_photo("photo1", photo_metadata)
                
                assert result is not None
                assert result.exists()
                assert result.read_bytes() == photo_content
    
    def test_download_photo_handles_duplicate_filenames(self, mock_config, temp_dir):
        """Should handle duplicate filenames by adding suffix."""
        mock_config.DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
        
        # Create existing file
        existing_file = mock_config.DOWNLOAD_DIR / "IMG_1234.jpg"
        existing_file.write_bytes(b"existing")
        
        photo_metadata = {
            "id": "photo1",
            "mediaType": "image",
            "mediaSubtypes": [],
        }
        
        with PhotoSyncClient(mock_config) as client:
            with patch.object(client, '_make_request') as mock_request:
                mock_response = MagicMock()
                mock_response.headers = {
                    "X-Original-Filename": "IMG_1234.jpg",
                    "X-Media-Type": "image",
                }
                mock_response.content = b"new photo"
                mock_request.return_value = mock_response
                
                result = client.download_photo("photo1", photo_metadata)
                
                assert result is not None
                assert result.name == "IMG_1234_1.jpg"
                assert existing_file.exists()  # Original unchanged
    
    def test_sync_downloads_new_photos(self, mock_config, temp_dir):
        """Full sync should download new photos and update state."""
        mock_config.DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
        
        photos_response = {
            "count": 1,
            "photos": [{
                "id": "photo1",
                "creationDate": "2024-01-15T10:30:00Z",
                "mediaType": "image",
                "mediaSubtypes": [],
            }]
        }
        
        with PhotoSyncClient(mock_config) as client:
            with patch.object(client, 'check_health', return_value=True):
                with patch.object(client, '_make_request') as mock_request:
                    # First call: list photos
                    list_response = MagicMock()
                    list_response.json.return_value = photos_response
                    
                    # Second call: download photo
                    download_response = MagicMock()
                    download_response.headers = {
                        "X-Original-Filename": "IMG_1234.jpg",
                        "X-Media-Type": "image",
                    }
                    download_response.content = b"photo data"
                    
                    mock_request.side_effect = [list_response, download_response]
                    
                    downloaded = client.sync()
                    
                    assert downloaded == 1
                    # State file should be updated
                    assert mock_config.STATE_FILE.exists()
    
    def test_sync_skips_when_server_unhealthy(self, mock_config, temp_dir):
        """Sync should skip if server health check fails."""
        mock_config.DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
        
        with PhotoSyncClient(mock_config) as client:
            with patch.object(client, 'check_health', return_value=False):
                downloaded = client.sync()
                
                assert downloaded == 0

