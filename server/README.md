# PhotoShare Server

Swift/Vapor REST API server for sharing photos from macOS Photos library.

## Quick Start

```bash
# Build
swift build

# Run (development)
swift run

# Run with custom secret
PHOTOSHARE_SECRET=your-secret swift run
```

## First Run

On first run, macOS will prompt for Photos library access. You must grant permission for the server to access your photos.

If the permission dialog doesn't appear:
1. Open System Preferences → Security & Privacy → Privacy → Photos
2. Click the lock to make changes
3. Add Terminal (or your IDE) to the list
4. Select "Full Access"

## Building for Release

```bash
swift build -c release
```

The executable will be at `.build/release/App`

## API Endpoints

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/health` | GET | No | Health check |
| `/photos` | GET | Yes | List photos (optional `?since=timestamp`) |
| `/photos/{id}` | GET | Yes | Get photo metadata |
| `/photos/{id}/download` | GET | Yes | Download full-resolution media |
| `/photos/{id}/livephoto` | GET | Yes | Download Live Photo (multipart) |

## Project Structure

```
server/
├── Package.swift           # Swift Package Manager manifest
├── Sources/
│   └── App/
│       ├── entrypoint.swift      # Application entry point
│       ├── configure.swift       # Server configuration
│       ├── routes.swift          # Route registration
│       ├── Controllers/
│       │   └── PhotoController.swift    # Photo API handlers
│       ├── Middleware/
│       │   └── HMACAuthMiddleware.swift # Authentication
│       └── Services/
│           └── PhotoLibraryService.swift # PhotoKit integration
└── Tests/
    └── AppTests/
        └── AppTests.swift        # Unit tests
```

## Testing

```bash
swift test
```

## Docker

This server requires macOS for PhotoKit access and cannot run in Docker.

