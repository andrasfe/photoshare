"""Integration tests for the PhotoShare client.

These tests verify the client works correctly with a mock server.
For real integration testing, run with a live server.
"""

import hashlib
import hmac
import json
import tempfile
import time
from pathlib import Path
from unittest.mock import MagicMock, patch

import httpx
import pytest

from auth import generate_auth_headers
from sync import PhotoSyncClient


class TestClientServerInteraction:
    """Tests simulating client-server interaction."""
    
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
        config.SHARED_SECRET = "integration-test-secret"
        config.DOWNLOAD_DIR = temp_dir / "downloads"
        config.STATE_FILE = temp_dir / ".sync_state"
        config.REQUEST_TIMEOUT = 30
        config.ensure_directories = MagicMock()
        return config
    
    def test_auth_headers_match_server_expectations(self):
        """Verify client auth headers match server HMAC verification."""
        secret = "shared-secret"
        method = "GET"
        path = "/photos"
        
        # Generate headers as client would
        headers = generate_auth_headers(method, path, secret)
        
        # Verify as server would
        timestamp = headers["X-Timestamp"]
        signature = headers["X-Signature"]
        
        # Server verification logic
        message = f"{method}:{path}:{timestamp}"
        expected_signature = hmac.new(
            secret.encode('utf-8'),
            message.encode('utf-8'),
            hashlib.sha256
        ).hexdigest()
        
        assert signature.lower() == expected_signature.lower()
    
    def test_full_sync_flow(self, mock_config, temp_dir):
        """Test complete sync flow from list to download."""
        mock_config.DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
        
        # Mock server responses
        photos_response = {
            "count": 2,
            "photos": [
                {
                    "id": "ABC123/L0/001",
                    "creationDate": "2024-01-15T10:30:00Z",
                    "modificationDate": "2024-01-15T10:30:00Z",
                    "mediaType": "image",
                    "mediaSubtypes": [],
                    "pixelWidth": 4032,
                    "pixelHeight": 3024,
                    "duration": 0,
                    "isFavorite": False,
                    "isHidden": False,
                    "location": None,
                },
                {
                    "id": "DEF456/L0/002",
                    "creationDate": "2024-01-16T14:20:00Z",
                    "modificationDate": "2024-01-16T14:20:00Z",
                    "mediaType": "video",
                    "mediaSubtypes": [],
                    "pixelWidth": 1920,
                    "pixelHeight": 1080,
                    "duration": 30.5,
                    "isFavorite": True,
                    "isHidden": False,
                    "location": {
                        "latitude": 37.7749,
                        "longitude": -122.4194,
                        "altitude": 10.5
                    },
                },
            ]
        }
        
        with PhotoSyncClient(mock_config) as client:
            with patch.object(client, 'check_health', return_value=True):
                with patch.object(client, '_make_request') as mock_request:
                    # Mock responses in order
                    list_response = MagicMock()
                    list_response.json.return_value = photos_response
                    
                    download1_response = MagicMock()
                    download1_response.headers = {
                        "X-Original-Filename": "IMG_1234.heic",
                        "X-Media-Type": "image",
                        "X-Creation-Date": "2024-01-15T10:30:00Z",
                    }
                    download1_response.content = b"fake heic data"
                    
                    download2_response = MagicMock()
                    download2_response.headers = {
                        "X-Original-Filename": "VID_5678.mov",
                        "X-Media-Type": "video",
                        "X-Creation-Date": "2024-01-16T14:20:00Z",
                    }
                    download2_response.content = b"fake video data"
                    
                    mock_request.side_effect = [
                        list_response,
                        download1_response,
                        download2_response,
                    ]
                    
                    downloaded = client.sync()
                    
                    assert downloaded == 2
                    
                    # Verify files were created
                    files = list(mock_config.DOWNLOAD_DIR.iterdir())
                    assert len(files) == 2
                    
                    # Verify state was saved
                    assert mock_config.STATE_FILE.exists()
    
    def test_incremental_sync_uses_last_timestamp(self, mock_config, temp_dir):
        """Verify incremental sync passes last sync time to server."""
        mock_config.DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
        
        # Set up existing sync state
        last_sync = 1700000000
        mock_config.STATE_FILE.write_text(json.dumps({
            "last_sync_timestamp": last_sync
        }))
        
        with PhotoSyncClient(mock_config) as client:
            with patch.object(client, 'check_health', return_value=True):
                with patch.object(client, '_make_request') as mock_request:
                    mock_response = MagicMock()
                    mock_response.json.return_value = {"count": 0, "photos": []}
                    mock_request.return_value = mock_response
                    
                    client.sync()
                    
                    # Verify the since parameter was included in the path
                    call_args = mock_request.call_args_list[0]
                    path = call_args[0][1]
                    assert f"since={last_sync}" in path
    
    def test_signature_uses_path_without_query_string(self, mock_config, temp_dir):
        """Verify HMAC signature is computed on path only (not query string)."""
        mock_config.DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
        
        with PhotoSyncClient(mock_config) as client:
            with patch('sync.generate_auth_headers') as mock_auth:
                mock_auth.return_value = {"X-Timestamp": "123", "X-Signature": "abc"}
                
                # Mock the HTTP client to avoid actual requests
                mock_http = MagicMock()
                mock_response = MagicMock()
                mock_response.json.return_value = {"count": 0, "photos": []}
                mock_http.request.return_value = mock_response
                client._client = mock_http
                
                # Call list_photos with since parameter
                client.list_photos(since=1700000000)
                
                # Verify auth headers were generated with path only (no query string)
                mock_auth.assert_called_once()
                call_args = mock_auth.call_args[0]
                assert call_args[1] == "/photos"  # Path without query string
    
    def test_live_photo_download_multipart(self, mock_config, temp_dir):
        """Test downloading a Live Photo with multipart response."""
        mock_config.DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
        
        photo_metadata = {
            "id": "LIVE123/L0/001",
            "mediaType": "image",
            "mediaSubtypes": ["livePhoto"],
        }
        
        # Create multipart response similar to server
        boundary = "test-boundary-12345"
        multipart_body = (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="photo"; filename="IMG_LIVE.heic"\r\n'
            f"Content-Type: image/heic\r\n\r\n"
            f"fake heic data"
            f"\r\n--{boundary}\r\n"
            f'Content-Disposition: form-data; name="video"; filename="IMG_LIVE.mov"\r\n'
            f"Content-Type: video/quicktime\r\n\r\n"
            f"fake video data"
            f"\r\n--{boundary}--\r\n"
        ).encode()
        
        with PhotoSyncClient(mock_config) as client:
            with patch.object(client, '_make_request') as mock_request:
                mock_response = MagicMock()
                mock_response.headers = {
                    "content-type": f"multipart/form-data; boundary={boundary}",
                    "X-Creation-Date": "2024-01-15T10:30:00Z",
                }
                mock_response.content = multipart_body
                mock_request.return_value = mock_response
                
                result = client.download_photo("LIVE123/L0/001", photo_metadata)
                
                assert result is not None
                # Should have created files for both components
                files = list(mock_config.DOWNLOAD_DIR.iterdir())
                assert len(files) >= 1  # At least the photo


class TestErrorHandling:
    """Tests for error handling in integration scenarios."""
    
    @pytest.fixture
    def temp_dir(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            yield Path(tmpdir)
    
    @pytest.fixture
    def mock_config(self, temp_dir):
        config = MagicMock()
        config.SERVER_URL = "http://localhost:8080"
        config.SHARED_SECRET = "test-secret"
        config.DOWNLOAD_DIR = temp_dir / "downloads"
        config.STATE_FILE = temp_dir / ".sync_state"
        config.REQUEST_TIMEOUT = 30
        config.ensure_directories = MagicMock()
        return config
    
    def test_handles_server_error_gracefully(self, mock_config, temp_dir):
        """Client should handle server errors without crashing."""
        mock_config.DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
        
        with PhotoSyncClient(mock_config) as client:
            with patch.object(client, 'check_health', return_value=True):
                with patch.object(client, '_make_request') as mock_request:
                    mock_request.side_effect = httpx.HTTPStatusError(
                        "Server Error",
                        request=MagicMock(),
                        response=MagicMock(status_code=500)
                    )
                    
                    # Should not raise
                    downloaded = client.sync()
                    assert downloaded == 0
    
    def test_handles_network_timeout(self, mock_config, temp_dir):
        """Client should handle network timeouts."""
        mock_config.DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
        
        with PhotoSyncClient(mock_config) as client:
            with patch.object(client, 'check_health', return_value=True):
                with patch.object(client, '_make_request') as mock_request:
                    mock_request.side_effect = httpx.TimeoutException("Timeout")
                    
                    downloaded = client.sync()
                    assert downloaded == 0
    
    def test_continues_after_single_download_failure(self, mock_config, temp_dir):
        """Should continue downloading other photos if one fails."""
        mock_config.DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
        
        photos_response = {
            "count": 2,
            "photos": [
                {"id": "photo1", "mediaType": "image", "mediaSubtypes": []},
                {"id": "photo2", "mediaType": "image", "mediaSubtypes": []},
            ]
        }
        
        with PhotoSyncClient(mock_config) as client:
            with patch.object(client, 'check_health', return_value=True):
                with patch.object(client, '_make_request') as mock_request:
                    list_response = MagicMock()
                    list_response.json.return_value = photos_response
                    
                    # First download fails
                    download1_error = httpx.HTTPStatusError(
                        "Not Found",
                        request=MagicMock(),
                        response=MagicMock(status_code=404)
                    )
                    
                    # Second download succeeds
                    download2_response = MagicMock()
                    download2_response.headers = {
                        "X-Original-Filename": "IMG_2.jpg",
                        "X-Media-Type": "image",
                    }
                    download2_response.content = b"photo data"
                    
                    mock_request.side_effect = [
                        list_response,
                        download1_error,
                        download2_response,
                    ]
                    
                    downloaded = client.sync()
                    
                    # Should have downloaded 1 of 2
                    assert downloaded == 1

