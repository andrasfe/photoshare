import Foundation
import SwiftUI
import Photos
import Vapor
import Crypto

@MainActor
class ServerManager: ObservableObject {
    @Published var isRunning = false
    @Published var photosAuthStatus: PHAuthorizationStatus = .notDetermined
    @Published var logs: [String] = []
    @Published var requestCount = 0
    @Published var photosServed = 0
    @Published var hasCustomSecret = false
    
    private var app: Application?
    private var startTime: Date?
    private var envVars: [String: String] = [:]
    
    var uptimeString: String {
        guard let start = startTime, isRunning else { return "--" }
        let interval = Date().timeIntervalSince(start)
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        
        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
    
    init() {
        loadEnvFile()
        checkPhotosAuth()
        hasCustomSecret = getEnv("PHOTOSHARE_SECRET") != nil
    }
    
    /// Load .env file from project root
    private func loadEnvFile() {
        // Try to find .env in common locations
        let possiblePaths = [
            // When running from Xcode or swift run in server-app
            FileManager.default.currentDirectoryPath + "/../.env",
            FileManager.default.currentDirectoryPath + "/.env",
            // Relative to executable
            Bundle.main.bundlePath + "/../../.env",
            Bundle.main.bundlePath + "/../../../.env",
            Bundle.main.bundlePath + "/../../../../.env",
            // Home directory fallback
            NSHomeDirectory() + "/photoshare/.env"
        ]
        
        for path in possiblePaths {
            let url = URL(fileURLWithPath: path).standardized
            if FileManager.default.fileExists(atPath: url.path) {
                parseEnvFile(at: url)
                return
            }
        }
    }
    
    private func parseEnvFile(at url: URL) {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return }
        
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            
            // Parse KEY=VALUE
            if let equalIndex = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[..<equalIndex]).trimmingCharacters(in: .whitespaces)
                var value = String(trimmed[trimmed.index(after: equalIndex)...]).trimmingCharacters(in: .whitespaces)
                
                // Remove quotes if present
                if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                   (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }
                
                envVars[key] = value
            }
        }
    }
    
    /// Get environment variable - checks .env first, then process environment
    func getEnv(_ key: String) -> String? {
        return envVars[key] ?? ProcessInfo.processInfo.environment[key]
    }
    
    func checkPhotosAuth() {
        photosAuthStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }
    
    func requestPhotosAccess() {
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            await MainActor.run {
                self.photosAuthStatus = status
                if status == .authorized {
                    self.log("Photos access granted")
                } else {
                    self.log("Photos access denied: \(status.rawValue)")
                }
            }
        }
    }
    
    func startServer() {
        guard !isRunning else { return }
        
        log("Starting server...")
        
        // Get secret before entering detached task
        let sharedSecret = getEnv("PHOTOSHARE_SECRET") ?? "development-secret-change-me"
        
        Task.detached { [weak self] in
            do {
                var env = try Environment.detect()
                try LoggingSystem.bootstrap(from: &env)
                
                let app = try await Application.make(env)
                
                await MainActor.run {
                    self?.app = app
                }
                
                // Configure
                app.storage[SharedSecretKey.self] = sharedSecret
                app.http.server.configuration.hostname = "0.0.0.0"
                app.http.server.configuration.port = 8080
                
                // Routes
                try await MainActor.run {
                    try self?.configureRoutes(app)
                }
                
                await MainActor.run {
                    self?.isRunning = true
                    self?.startTime = Date()
                    self?.log("Server started on http://0.0.0.0:8080")
                }
                
                try await app.execute()
                
            } catch {
                await MainActor.run {
                    self?.log("Server error: \(error.localizedDescription)")
                    self?.isRunning = false
                }
            }
        }
    }
    
    func stopServer() {
        guard isRunning else { return }
        
        log("Stopping server...")
        
        Task {
            try? await app?.asyncShutdown()
            await MainActor.run {
                self.app = nil
                self.isRunning = false
                self.startTime = nil
                self.log("Server stopped")
            }
        }
    }
    
    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(timestamp)] \(message)"
        logs.append(entry)
        
        // Keep only last 1000 logs
        if logs.count > 1000 {
            logs.removeFirst(logs.count - 1000)
        }
    }
    
    // MARK: - Route Configuration
    
    private func configureRoutes(_ app: Application) throws {
        // Health check
        app.get("health") { [weak self] req -> String in
            Task { @MainActor in
                self?.requestCount += 1
            }
            return "OK"
        }
        
        // Protected routes
        let protected = app.grouped(HMACAuthMiddleware())
        
        // List photos
        protected.get("photos") { [weak self] req -> PhotoListResponse in
            Task { @MainActor in
                self?.requestCount += 1
            }
            
            let sinceTimestamp: Double? = req.query["since"]
            let sinceDate = sinceTimestamp.map { Date(timeIntervalSince1970: $0) }
            
            let photos = try await self?.fetchPhotos(since: sinceDate) ?? []
            
            return PhotoListResponse(count: photos.count, photos: photos)
        }
        
        // Get photo metadata
        protected.get("photos", ":id") { [weak self] req -> PhotoMetadata in
            Task { @MainActor in
                self?.requestCount += 1
            }
            
            guard let id = req.parameters.get("id") else {
                throw Abort(.badRequest, reason: "Missing photo ID")
            }
            
            guard let photo = try await self?.fetchPhoto(id: id) else {
                throw Abort(.notFound, reason: "Photo not found")
            }
            
            return photo
        }
        
        // Download photo
        protected.get("photos", ":id", "download") { [weak self] req -> Response in
            Task { @MainActor in
                self?.requestCount += 1
                self?.photosServed += 1
            }
            
            guard let id = req.parameters.get("id") else {
                throw Abort(.badRequest, reason: "Missing photo ID")
            }
            
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
            guard let asset = result.firstObject else {
                throw Abort(.notFound, reason: "Photo not found")
            }
            
            let (data, filename, uti) = try await self?.exportAssetData(asset: asset) ?? (Data(), "photo.jpg", "public.jpeg")
            
            let contentType = Self.mimeType(from: uti)
            var headers = HTTPHeaders()
            headers.add(name: .contentType, value: contentType)
            headers.add(name: .contentDisposition, value: "attachment; filename=\"\(filename)\"")
            headers.add(name: "X-Original-Filename", value: filename)
            headers.add(name: "X-Media-Type", value: asset.mediaType == .video ? "video" : "image")
            
            return Response(status: .ok, headers: headers, body: .init(data: data))
        }
    }
    
    // MARK: - PhotoKit Integration
    
    private func fetchPhotos(since: Date?) async throws -> [PhotoMetadata] {
        guard photosAuthStatus == .authorized || photosAuthStatus == .limited else {
            throw Abort(.forbidden, reason: "Photos access not granted")
        }
        
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        
        if let sinceDate = since {
            fetchOptions.predicate = NSPredicate(format: "creationDate > %@", sinceDate as NSDate)
        }
        
        let assets = PHAsset.fetchAssets(with: fetchOptions)
        
        var photos: [PhotoMetadata] = []
        assets.enumerateObjects { asset, _, _ in
            photos.append(PhotoMetadata(from: asset))
        }
        
        return photos
    }
    
    private func fetchPhoto(id: String) async throws -> PhotoMetadata? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = result.firstObject else { return nil }
        return PhotoMetadata(from: asset)
    }
    
    private func exportAssetData(asset: PHAsset) async throws -> (Data, String, String) {
        return try await withCheckedThrowingContinuation { continuation in
            let resources = PHAssetResource.assetResources(for: asset)
            
            guard let resource = resources.first(where: {
                $0.type == .photo || $0.type == .video || $0.type == .fullSizePhoto || $0.type == .fullSizeVideo
            }) ?? resources.first else {
                continuation.resume(throwing: Abort(.notFound, reason: "No resource found"))
                return
            }
            
            var data = Data()
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            
            PHAssetResourceManager.default().requestData(for: resource, options: options) { chunk in
                data.append(chunk)
            } completionHandler: { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (data, resource.originalFilename, resource.uniformTypeIdentifier))
                }
            }
        }
    }
    
    private static func mimeType(from uti: String) -> String {
        let mapping: [String: String] = [
            "public.jpeg": "image/jpeg",
            "public.png": "image/png",
            "public.heic": "image/heic",
            "public.heif": "image/heif",
            "com.adobe.raw-image": "image/x-adobe-dng",
            "public.tiff": "image/tiff",
            "com.compuserve.gif": "image/gif",
            "public.mpeg-4": "video/mp4",
            "com.apple.quicktime-movie": "video/quicktime",
            "public.movie": "video/mp4",
        ]
        return mapping[uti] ?? "application/octet-stream"
    }
}

// MARK: - Storage Key

struct SharedSecretKey: StorageKey {
    typealias Value = String
}

// MARK: - HMAC Middleware

struct HMACAuthMiddleware: AsyncMiddleware {
    /// Maximum allowed time difference between client and server (5 minutes)
    private let maxTimeDrift: TimeInterval = 300
    
    /// Expected signature length (SHA256 = 64 hex chars)
    private let expectedSignatureLength = 64
    
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // 1. Validate shared secret is configured and not default
        guard let sharedSecret = request.application.storage[SharedSecretKey.self],
              !sharedSecret.isEmpty,
              sharedSecret != "development-secret-change-me" else {
            request.logger.error("SECURITY: Server has no valid shared secret configured")
            throw Abort(.internalServerError, reason: "Server configuration error")
        }
        
        // 2. Validate X-Timestamp header exists and is valid
        guard let timestampString = request.headers.first(name: "X-Timestamp") else {
            request.logger.warning("SECURITY: Missing X-Timestamp header from \(request.remoteAddress?.description ?? "unknown")")
            throw Abort(.unauthorized, reason: "Missing X-Timestamp header")
        }
        
        guard let timestamp = Double(timestampString) else {
            request.logger.warning("SECURITY: Invalid X-Timestamp format from \(request.remoteAddress?.description ?? "unknown")")
            throw Abort(.unauthorized, reason: "Invalid X-Timestamp header")
        }
        
        // 3. Validate X-Signature header exists and has correct format
        guard let signature = request.headers.first(name: "X-Signature") else {
            request.logger.warning("SECURITY: Missing X-Signature header from \(request.remoteAddress?.description ?? "unknown")")
            throw Abort(.unauthorized, reason: "Missing X-Signature header")
        }
        
        // Validate signature format (must be hex string of correct length)
        guard signature.count == expectedSignatureLength,
              signature.allSatisfy({ $0.isHexDigit }) else {
            request.logger.warning("SECURITY: Invalid signature format from \(request.remoteAddress?.description ?? "unknown")")
            throw Abort(.unauthorized, reason: "Invalid signature format")
        }
        
        // 4. Validate timestamp is within acceptable range (prevents replay attacks)
        let now = Date().timeIntervalSince1970
        let timeDiff = abs(now - timestamp)
        
        if timeDiff > maxTimeDrift {
            request.logger.warning("SECURITY: Expired timestamp (\(Int(timeDiff))s drift) from \(request.remoteAddress?.description ?? "unknown")")
            throw Abort(.unauthorized, reason: "Request timestamp expired")
        }
        
        // 5. Build and verify signature
        let message = "\(request.method.rawValue):\(request.url.path):\(timestampString)"
        
        let key = SymmetricKey(data: Data(sharedSecret.utf8))
        let expectedMAC = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        
        // Convert provided signature to Data for constant-time comparison
        guard let providedSignatureData = Data(hexString: signature.lowercased()) else {
            request.logger.warning("SECURITY: Could not decode signature hex from \(request.remoteAddress?.description ?? "unknown")")
            throw Abort(.unauthorized, reason: "Invalid signature")
        }
        
        // Constant-time comparison using CryptoKit
        let expectedData = Data(expectedMAC)
        guard constantTimeCompare(expectedData, providedSignatureData) else {
            request.logger.warning("SECURITY: Signature mismatch for \(request.method.rawValue) \(request.url.path) from \(request.remoteAddress?.description ?? "unknown")")
            throw Abort(.unauthorized, reason: "Invalid signature")
        }
        
        request.logger.debug("HMAC auth successful for \(request.method.rawValue) \(request.url.path)")
        return try await next.respond(to: request)
    }
    
    /// Constant-time comparison to prevent timing attacks
    private func constantTimeCompare(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var result: UInt8 = 0
        for (x, y) in zip(a, b) {
            result |= x ^ y
        }
        return result == 0
    }
}

// MARK: - Data Hex Extension

extension Data {
    init?(hexString: String) {
        let len = hexString.count
        guard len % 2 == 0 else { return nil }
        
        var data = Data(capacity: len / 2)
        var index = hexString.startIndex
        
        for _ in 0..<(len / 2) {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }
        
        self = data
    }
}

// MARK: - Models

struct PhotoMetadata: Content {
    let id: String
    let creationDate: Date?
    let modificationDate: Date?
    let mediaType: String
    let mediaSubtypes: [String]
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: Double
    let isFavorite: Bool
    let isHidden: Bool
    
    init(from asset: PHAsset) {
        self.id = asset.localIdentifier
        self.creationDate = asset.creationDate
        self.modificationDate = asset.modificationDate
        self.pixelWidth = asset.pixelWidth
        self.pixelHeight = asset.pixelHeight
        self.duration = asset.duration
        self.isFavorite = asset.isFavorite
        self.isHidden = asset.isHidden
        
        switch asset.mediaType {
        case .image: self.mediaType = "image"
        case .video: self.mediaType = "video"
        case .audio: self.mediaType = "audio"
        default: self.mediaType = "unknown"
        }
        
        var subtypes: [String] = []
        if asset.mediaSubtypes.contains(.photoLive) { subtypes.append("livePhoto") }
        if asset.mediaSubtypes.contains(.photoHDR) { subtypes.append("hdr") }
        if asset.mediaSubtypes.contains(.photoPanorama) { subtypes.append("panorama") }
        if asset.mediaSubtypes.contains(.photoScreenshot) { subtypes.append("screenshot") }
        self.mediaSubtypes = subtypes
    }
}

struct PhotoListResponse: Content {
    let count: Int
    let photos: [PhotoMetadata]
}

