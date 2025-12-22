# PhotoShare

A client-server application for sharing photos from macOS Photos app over a REST API with HMAC authentication.

## Architecture

```
┌─────────────────┐         HTTPS/HTTP          ┌─────────────────┐
│  Python Client  │ ◄─────────────────────────► │  Swift Server   │
│                 │    HMAC-SHA256 Auth         │    (Vapor)      │
│  - Polls hourly │                             │                 │
│  - Downloads    │                             │  - PhotoKit     │
│  - Incremental  │                             │  - REST API     │
└─────────────────┘                             └────────┬────────┘
                                                         │
                                                         ▼
                                                ┌─────────────────┐
                                                │  macOS Photos   │
                                                │    Library      │
                                                └─────────────────┘
```

## Components

### Server (Swift/Vapor)

The server runs on macOS and exposes the Photos library via REST API.

**Location:** `server/`

**Features:**
- REST API for listing and downloading photos
- HMAC-SHA256 authentication with shared secret
- Full-resolution photo/video export
- Support for all media types (JPEG, HEIC, RAW, Live Photos, videos)
- PhotoKit integration for native Photos app access

### Client (Python)

The client polls the server and downloads new photos. Available as both CLI and Web UI.

**Location:** `client/`

**Features:**
- **CLI Mode**: Hourly polling (configurable), runs in background
- **Web UI**: Modern interface with real-time progress
- Incremental sync (only downloads new photos)
- HMAC authentication matching server
- Retry logic with error handling
- Live Photo support (downloads both image and video)
- Date filtering for selective sync

## Setup

### Prerequisites

**Server:**
- macOS 13+ (Ventura or later)
- Xcode 15+ with Command Line Tools
- Swift 5.9+

**Client:**
- Python 3.10+

### Server Setup

1. Navigate to the server directory:
   ```bash
   cd server
   ```

2. Build the project:
   ```bash
   swift build
   ```

3. Create a `.env` file with your shared secret:
   ```bash
   echo 'PHOTOSHARE_SECRET=your-secure-secret-here' > .env
   ```
   
   Generate a secure secret:
   ```bash
   openssl rand -hex 32
   ```

4. Run the server:
   ```bash
   swift run
   ```

5. **First run:** The server will request Photos library access. Grant permission when prompted.

### Client Setup

1. Navigate to the client directory:
   ```bash
   cd client
   ```

2. Create a virtual environment:
   ```bash
   python3 -m venv venv
   source venv/bin/activate
   ```

3. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

4. Create a `.env` file:
   ```bash
   cat > .env << EOF
   PHOTOSHARE_SERVER_URL=http://your-server-ip:8080
   PHOTOSHARE_SECRET=your-secure-secret-here
   PHOTOSHARE_DOWNLOAD_DIR=./downloads
   PHOTOSHARE_POLL_INTERVAL=1
   EOF
   ```

5. Run the client:

   **Option A: Web UI (Recommended)**
   ```bash
   python run_web.py
   # Open http://localhost:8000 in your browser
   ```

   **Option B: CLI - continuous polling**
   ```bash
   python main.py
   ```

   **Option C: CLI - run once**
   ```bash
   python main.py --once
   ```

## API Reference

### Authentication

All endpoints (except `/health`) require HMAC authentication via headers:

| Header | Description |
|--------|-------------|
| `X-Timestamp` | Unix timestamp (must be within 5 minutes of server time) |
| `X-Signature` | HMAC-SHA256 of `{method}:{path}:{timestamp}` |

### Endpoints

#### Health Check
```
GET /health
```
No authentication required. Returns `OK` if server is running.

#### List Photos
```
GET /photos?since=<timestamp>
```
Returns JSON list of photo metadata.

**Query Parameters:**
- `since` (optional): Unix timestamp to filter photos created after

**Response:**
```json
{
  "count": 2,
  "photos": [
    {
      "id": "ABC123/L0/001",
      "creationDate": "2024-01-15T10:30:00Z",
      "mediaType": "image",
      "mediaSubtypes": ["livePhoto"],
      "pixelWidth": 4032,
      "pixelHeight": 3024,
      "isFavorite": false,
      "location": {
        "latitude": 37.7749,
        "longitude": -122.4194,
        "altitude": 10.5
      }
    }
  ]
}
```

#### Get Photo Metadata
```
GET /photos/{id}
```
Returns metadata for a specific photo.

#### Download Photo
```
GET /photos/{id}/download
```
Downloads the full-resolution photo or video.

**Response Headers:**
- `Content-Type`: MIME type of the media
- `Content-Disposition`: `attachment; filename="..."`
- `X-Original-Filename`: Original filename
- `X-Media-Type`: `image` or `video`
- `X-Creation-Date`: ISO 8601 creation date

#### Download Live Photo
```
GET /photos/{id}/livephoto
```
Downloads Live Photo as multipart response containing both HEIC image and MOV video.

## Configuration

### Server Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PHOTOSHARE_SECRET` | `development-secret-change-me` | HMAC shared secret |

### Client Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PHOTOSHARE_SERVER_URL` | `http://localhost:8080` | Server URL |
| `PHOTOSHARE_SECRET` | `development-secret-change-me` | HMAC shared secret |
| `PHOTOSHARE_DOWNLOAD_DIR` | `./downloads` | Download directory |
| `PHOTOSHARE_POLL_INTERVAL` | `1` | Polling interval in hours |
| `PHOTOSHARE_TIMEOUT` | `300` | Request timeout in seconds |
| `PHOTOSHARE_MAX_RETRIES` | `3` | Maximum retry attempts |

## Security Considerations

1. **Shared Secret**: Use a strong, randomly generated secret (at least 32 bytes)
2. **HTTPS**: For production use over the internet, put the server behind a reverse proxy with TLS
3. **Network**: Consider running on a private network or VPN
4. **Timestamp Validation**: Requests expire after 5 minutes to prevent replay attacks

## Troubleshooting

### Server: "Photos library access denied"

1. Open System Preferences → Security & Privacy → Privacy → Photos
2. Add the terminal app or the built executable
3. Grant "Full Access"

### Client: "Invalid signature"

- Ensure the shared secret matches on both client and server
- Check that system clocks are synchronized (within 5 minutes)

### Client: Connection refused

- Verify server is running: `curl http://localhost:8080/health`
- Check firewall settings
- Ensure correct IP/port in client configuration

## Disclaimer

THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES, OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT, OR OTHERWISE, ARISING FROM, OUT OF, OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

**Use at your own risk.** The authors are not responsible for:
- Any data loss, corruption, or unauthorized access to your photos
- Any damage to your devices or systems
- Any privacy or security breaches resulting from use of this software
- Any violations of Apple's terms of service or local laws

This software accesses your Photos library and transmits data over the network. Ensure you understand the security implications before use.

## License

MIT

