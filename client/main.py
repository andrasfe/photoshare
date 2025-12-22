#!/usr/bin/env python3
"""
PhotoShare Client - Continuously syncs photos from a PhotoShare server.

Usage:
    python main.py [--once] [--interval HOURS]

Options:
    --once          Run sync once and exit
    --interval      Override poll interval (default: 1 hour)
"""

import argparse
import logging
import signal
import sys
import time
from datetime import datetime

import schedule

from config import Config
from sync import PhotoSyncClient

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

# Global flag for graceful shutdown
shutdown_requested = False


def signal_handler(signum, frame):
    """Handle shutdown signals gracefully."""
    global shutdown_requested
    logger.info("Shutdown signal received, finishing current operation...")
    shutdown_requested = True


def run_sync():
    """Execute a single sync operation."""
    logger.info(f"=== Sync started at {datetime.now().isoformat()} ===")
    
    try:
        with PhotoSyncClient() as client:
            # Check server health first
            if not client.check_health():
                logger.error("Server health check failed, skipping sync")
                return
            
            downloaded = client.sync()
            logger.info(f"Sync completed: {downloaded} photos downloaded")
            
    except Exception as e:
        logger.exception(f"Sync failed with error: {e}")


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description="PhotoShare sync client")
    parser.add_argument(
        "--once",
        action="store_true",
        help="Run sync once and exit",
    )
    parser.add_argument(
        "--interval",
        type=int,
        default=Config.POLL_INTERVAL_HOURS,
        help=f"Poll interval in hours (default: {Config.POLL_INTERVAL_HOURS})",
    )
    args = parser.parse_args()
    
    # Validate configuration
    if not Config.validate():
        sys.exit(1)
    
    logger.info("PhotoShare Client starting...")
    logger.info(f"Server: {Config.SERVER_URL}")
    logger.info(f"Download directory: {Config.DOWNLOAD_DIR}")
    
    # Set up signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    if args.once:
        # Single sync mode
        run_sync()
    else:
        # Continuous polling mode
        interval_hours = args.interval
        logger.info(f"Starting continuous sync every {interval_hours} hour(s)")
        
        # Run immediately on startup
        run_sync()
        
        # Schedule periodic runs
        schedule.every(interval_hours).hours.do(run_sync)
        
        # Main loop
        while not shutdown_requested:
            schedule.run_pending()
            time.sleep(60)  # Check every minute
        
        logger.info("Shutdown complete")


if __name__ == "__main__":
    main()

