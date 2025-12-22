#!/usr/bin/env python3
"""
Start the PhotoShare Web Client.

Usage:
    python run_web.py [--host HOST] [--port PORT]
"""

import argparse
import uvicorn


def main():
    parser = argparse.ArgumentParser(description="PhotoShare Web Client")
    parser.add_argument("--host", default="0.0.0.0", help="Host to bind to (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=8000, help="Port to bind to (default: 8000)")
    parser.add_argument("--reload", action="store_true", help="Enable auto-reload for development")
    args = parser.parse_args()

    print(f"""
╔══════════════════════════════════════════════════════════════╗
║                    PhotoShare Web Client                      ║
╠══════════════════════════════════════════════════════════════╣
║  Open http://{args.host}:{args.port} in your browser              ║
║  Press Ctrl+C to stop                                         ║
╚══════════════════════════════════════════════════════════════╝
    """)

    uvicorn.run(
        "web.app:app",
        host=args.host,
        port=args.port,
        reload=args.reload,
    )


if __name__ == "__main__":
    main()

