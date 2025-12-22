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
        checkPhotosAuth()
        hasCustomSecret = ProcessInfo.processInfo.environment["PHOTOSHARE_SECRET"] != nil
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
        
        Task.detached { [weak self] in
            do {
                var env = try Environment.detect()
                try LoggingSystem.bootstrap(from: &env)
                
                let app = try await Application.make(env)
                
                await MainActor.run {
                    self?.app = app
                }
                
                // Configure
                let sharedSecret = Environment.get("PHOTOSHARE_SECRET") ?? "development-secret-change-me"
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
    private let maxTimeDrift: TimeInterval = 300
    
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let timestampString = request.headers.first(name: "X-Timestamp"),
              let timestamp = Double(timestampString) else {
            throw Abort(.unauthorized, reason: "Missing or invalid X-Timestamp header")
        }
        
        guard let signature = request.headers.first(name: "X-Signature") else {
            throw Abort(.unauthorized, reason: "Missing X-Signature header")
        }
        
        let now = Date().timeIntervalSince1970
        if abs(now - timestamp) > maxTimeDrift {
            throw Abort(.unauthorized, reason: "Request timestamp expired")
        }
        
        let sharedSecret = request.application.storage[SharedSecretKey.self] ?? ""
        let message = "\(request.method.rawValue):\(request.url.path):\(timestampString)"
        
        let key = SymmetricKey(data: Data(sharedSecret.utf8))
        let expectedSignature = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        let expectedSignatureHex = expectedSignature.map { String(format: "%02x", $0) }.joined()
        
        guard signature.lowercased() == expectedSignatureHex.lowercased() else {
            throw Abort(.unauthorized, reason: "Invalid signature")
        }
        
        return try await next.respond(to: request)
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

