# PhotoShare

Share photos from your macOS Photos library over a REST API.

## Quick Start

### 1. Start the Server (macOS only)

```bash
cd server-app
swift build
open .build/debug/PhotoShareServer
```

In the app window:
- Click **"Request Access"** to grant Photos permission
- Click **"Start Server"**

### 2. Start the Client

```bash
./start.sh client
```

Open **http://localhost:8000** in your browser.

## Components

| Component | Description |
|-----------|-------------|
| `server-app/` | SwiftUI macOS app - serves photos from Photos library |
| `client/` | Python web client - syncs photos from server |

## Configuration

Set these environment variables before starting:

```bash
export PHOTOSHARE_SECRET=your-secure-secret-here
export PHOTOSHARE_SERVER_URL=http://server-ip:8080  # for client
```

Generate a secure secret: `openssl rand -hex 32`

## API

| Endpoint | Description |
|----------|-------------|
| `GET /health` | Health check |
| `GET /photos?since=timestamp` | List photos |
| `GET /photos/{id}/download` | Download photo |

All endpoints except `/health` require HMAC authentication.

## Disclaimer

THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND. The authors are not responsible for any data loss, damage, or security issues. Use at your own risk.

## License

MIT
