"""Unit tests for the config module."""

import os
from pathlib import Path
from unittest.mock import patch

import pytest

# Import after potentially patching environment
from config import Config


class TestConfig:
    """Tests for Config class."""
    
    def test_default_server_url(self):
        """Should have sensible default server URL."""
        with patch.dict(os.environ, {}, clear=True):
            # Re-import to get fresh config
            import importlib
            import config
            importlib.reload(config)
            
            assert config.Config.SERVER_URL == "http://localhost:8080"
    
    def test_server_url_from_env(self):
        """Should read server URL from environment."""
        with patch.dict(os.environ, {"PHOTOSHARE_SERVER_URL": "http://custom:9000"}):
            import importlib
            import config
            importlib.reload(config)
            
            assert config.Config.SERVER_URL == "http://custom:9000"
    
    def test_default_poll_interval(self):
        """Should default to 1 hour poll interval."""
        with patch.dict(os.environ, {}, clear=True):
            import importlib
            import config
            importlib.reload(config)
            
            assert config.Config.POLL_INTERVAL_HOURS == 1
    
    def test_poll_interval_from_env(self):
        """Should read poll interval from environment."""
        with patch.dict(os.environ, {"PHOTOSHARE_POLL_INTERVAL": "2"}):
            import importlib
            import config
            importlib.reload(config)
            
            assert config.Config.POLL_INTERVAL_HOURS == 2
    
    def test_validate_warns_about_default_secret(self, capsys):
        """Should warn when using default secret."""
        with patch.dict(os.environ, {"PHOTOSHARE_SECRET": "development-secret-change-me"}):
            import importlib
            import config
            importlib.reload(config)
            
            result = config.Config.validate()
            captured = capsys.readouterr()
            
            assert result is True  # Still valid, just a warning
            assert "WARNING" in captured.out
    
    def test_validate_returns_false_without_server_url(self, capsys):
        """Should fail validation if server URL is empty."""
        import importlib
        import config
        importlib.reload(config)
        
        # Temporarily set empty URL
        original_url = config.Config.SERVER_URL
        config.Config.SERVER_URL = ""
        
        try:
            result = config.Config.validate()
            captured = capsys.readouterr()
            
            assert result is False
            assert "ERROR" in captured.out
        finally:
            config.Config.SERVER_URL = original_url
    
    def test_ensure_directories_creates_download_dir(self, tmp_path):
        """Should create download directory if it doesn't exist."""
        import importlib
        import config
        importlib.reload(config)
        
        download_dir = tmp_path / "new_downloads"
        config.Config.DOWNLOAD_DIR = download_dir
        
        assert not download_dir.exists()
        
        config.Config.ensure_directories()
        
        assert download_dir.exists()
        assert download_dir.is_dir()
    
    def test_download_dir_is_path_object(self):
        """DOWNLOAD_DIR should be a Path object."""
        import importlib
        import config
        importlib.reload(config)
        
        assert isinstance(config.Config.DOWNLOAD_DIR, Path)
    
    def test_state_file_is_path_object(self):
        """STATE_FILE should be a Path object."""
        import importlib
        import config
        importlib.reload(config)
        
        assert isinstance(config.Config.STATE_FILE, Path)
    
    def test_request_timeout_default(self):
        """Should have sensible default timeout."""
        with patch.dict(os.environ, {}, clear=True):
            import importlib
            import config
            importlib.reload(config)
            
            # Default 5 minutes for large file downloads
            assert config.Config.REQUEST_TIMEOUT == 300
    
    def test_max_retries_default(self):
        """Should have sensible default max retries."""
        with patch.dict(os.environ, {}, clear=True):
            import importlib
            import config
            importlib.reload(config)
            
            assert config.Config.MAX_RETRIES == 3

