"""Configuration management for PhotoShare client."""

import os
from pathlib import Path
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()


class Config:
    """Application configuration loaded from environment variables."""
    
    # Server connection
    SERVER_URL: str = os.getenv("PHOTOSHARE_SERVER_URL", "http://localhost:8080")
    SHARED_SECRET: str = os.getenv("PHOTOSHARE_SECRET", "development-secret-change-me")
    
    # Sync settings
    POLL_INTERVAL_HOURS: int = int(os.getenv("PHOTOSHARE_POLL_INTERVAL", "1"))
    DOWNLOAD_DIR: Path = Path(os.getenv("PHOTOSHARE_DOWNLOAD_DIR", "./downloads"))
    
    # State file to track last sync timestamp
    STATE_FILE: Path = Path(os.getenv("PHOTOSHARE_STATE_FILE", "./.sync_state"))
    
    # Request settings
    REQUEST_TIMEOUT: int = int(os.getenv("PHOTOSHARE_TIMEOUT", "300"))  # 5 minutes for large files
    MAX_RETRIES: int = int(os.getenv("PHOTOSHARE_MAX_RETRIES", "3"))
    
    @classmethod
    def validate(cls) -> bool:
        """Validate that required configuration is present."""
        if cls.SHARED_SECRET == "development-secret-change-me":
            print("WARNING: Using default shared secret. Set PHOTOSHARE_SECRET for production!")
        
        if not cls.SERVER_URL:
            print("ERROR: PHOTOSHARE_SERVER_URL is required")
            return False
        
        return True
    
    @classmethod
    def ensure_directories(cls) -> None:
        """Ensure required directories exist."""
        cls.DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)

