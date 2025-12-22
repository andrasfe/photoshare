import Vapor
import Photos

struct PhotoController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let photos = routes.grouped("photos")
        
        photos.get(use: listPhotos)
        photos.get(":id", use: getPhoto)
        photos.get(":id", "download", use: downloadPhoto)
        photos.get(":id", "livephoto", use: downloadLivePhoto)
    }
    
    // MARK: - List Photos
    
    /// GET /photos?since=<unix_timestamp>
    /// Returns list of photo metadata for photos created after the given timestamp
    @Sendable
    func listPhotos(req: Request) async throws -> PhotoListResponse {
        // Parse optional 'since' query parameter
        let sinceTimestamp: Double? = req.query["since"]
        let sinceDate = sinceTimestamp.map { Date(timeIntervalSince1970: $0) }
        
        req.logger.info("Fetching photos since: \(sinceDate?.description ?? "all time")")
        
        let photos = try await PhotoLibraryService.shared.fetchPhotos(since: sinceDate)
        
        return PhotoListResponse(
            count: photos.count,
            photos: photos
        )
    }
    
    // MARK: - Get Photo Metadata
    
    /// GET /photos/:id
    /// Returns metadata for a specific photo
    @Sendable
    func getPhoto(req: Request) async throws -> PhotoMetadata {
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Missing photo ID")
        }
        
        guard let photo = try await PhotoLibraryService.shared.fetchPhoto(id: id) else {
            throw Abort(.notFound, reason: "Photo not found")
        }
        
        return photo
    }
    
    // MARK: - Download Photo
    
    /// GET /photos/:id/download
    /// Downloads the full-resolution photo/video data
    @Sendable
    func downloadPhoto(req: Request) async throws -> Response {
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Missing photo ID")
        }
        
        guard let asset = try await PhotoLibraryService.shared.getAsset(id: id) else {
            throw Abort(.notFound, reason: "Photo not found")
        }
        
        req.logger.info("Downloading asset: \(id)")
        
        let (data, filename, uti) = try await PhotoLibraryService.shared.exportAssetData(asset: asset)
        
        // Determine content type from UTI
        let contentType = mimeType(from: uti)
        
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: contentType)
        headers.add(name: .contentDisposition, value: "attachment; filename=\"\(filename)\"")
        headers.add(name: "X-Original-Filename", value: filename)
        headers.add(name: "X-Media-Type", value: asset.mediaType == .video ? "video" : "image")
        headers.add(name: "X-Creation-Date", value: asset.creationDate?.iso8601String ?? "")
        
        return Response(
            status: .ok,
            headers: headers,
            body: .init(data: data)
        )
    }
    
    // MARK: - Download Live Photo
    
    /// GET /photos/:id/livephoto
    /// Downloads Live Photo as multipart response with both image and video
    @Sendable
    func downloadLivePhoto(req: Request) async throws -> Response {
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Missing photo ID")
        }
        
        guard let asset = try await PhotoLibraryService.shared.getAsset(id: id) else {
            throw Abort(.notFound, reason: "Photo not found")
        }
        
        // Verify this is actually a Live Photo
        guard asset.mediaSubtypes.contains(.photoLive) else {
            throw Abort(.badRequest, reason: "This asset is not a Live Photo. Use /download endpoint instead.")
        }
        
        req.logger.info("Downloading Live Photo: \(id)")
        
        let livePhotoData = try await PhotoLibraryService.shared.exportLivePhotoData(asset: asset)
        
        // Create multipart response
        let boundary = UUID().uuidString
        var body = Data()
        
        // Add photo part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"\(livePhotoData.photoFilename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/heic\r\n\r\n".data(using: .utf8)!)
        body.append(livePhotoData.photoData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add video part if available
        if let videoData = livePhotoData.videoData {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"video\"; filename=\"\(livePhotoData.videoFilename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: video/quicktime\r\n\r\n".data(using: .utf8)!)
            body.append(videoData)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "multipart/form-data; boundary=\(boundary)")
        headers.add(name: "X-Creation-Date", value: asset.creationDate?.iso8601String ?? "")
        
        return Response(
            status: .ok,
            headers: headers,
            body: .init(data: body)
        )
    }
    
    // MARK: - Helpers
    
    private func mimeType(from uti: String) -> String {
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

// MARK: - Response Models

struct PhotoListResponse: Content {
    let count: Int
    let photos: [PhotoMetadata]
}

// MARK: - Date Extension

extension Date {
    var iso8601String: String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: self)
    }
}

