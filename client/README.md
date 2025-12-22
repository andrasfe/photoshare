# PhotoShare Client

Python client for syncing photos from a PhotoShare server.

## Quick Start

```bash
# Setup
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Configure
export PHOTOSHARE_SERVER_URL=http://your-server:8080
export PHOTOSHARE_SECRET=your-shared-secret

# Run (continuous polling)
python main.py

# Run once
python main.py --once
```

## Configuration

Create a `.env` file or set environment variables:

```bash
PHOTOSHARE_SERVER_URL=http://localhost:8080
PHOTOSHARE_SECRET=your-shared-secret
PHOTOSHARE_DOWNLOAD_DIR=./downloads
PHOTOSHARE_POLL_INTERVAL=1
```

## Usage

### Continuous Mode (Default)

Polls the server every hour (configurable) and downloads new photos:

```bash
python main.py
```

### Single Sync

Run once and exit:

```bash
python main.py --once
```

### Custom Interval

```bash
python main.py --interval 2  # Poll every 2 hours
```

## Project Structure

```
client/
├── requirements.txt    # Python dependencies
├── config.py          # Configuration management
├── auth.py            # HMAC authentication
├── sync.py            # Sync logic
└── main.py            # Entry point
```

## How It Works

1. Client reads last sync timestamp from `.sync_state`
2. Queries server for photos newer than that timestamp
3. Downloads each photo one-by-one
4. Saves new sync timestamp
5. Waits for next poll interval (or exits if `--once`)

## Files

- `.sync_state` - Tracks last successful sync timestamp
- `downloads/` - Default directory for downloaded photos (configurable)

## Logs

The client logs to stdout with timestamps:

```
2024-01-15 10:30:00 [INFO] PhotoShare Client starting...
2024-01-15 10:30:00 [INFO] Server: http://localhost:8080
2024-01-15 10:30:00 [INFO] Starting continuous sync every 1 hour(s)
2024-01-15 10:30:01 [INFO] Found 5 photos
2024-01-15 10:30:02 [INFO] Downloaded: downloads/IMG_1234.heic
```

