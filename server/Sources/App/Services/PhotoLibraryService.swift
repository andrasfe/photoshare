import Foundation
import Photos
import Vapor

/// Service for interacting with the macOS Photos library via PhotoKit
actor PhotoLibraryService {
    static let shared = PhotoLibraryService()
    
    private var isAuthorized = false
    
    private init() {}
    
    // MARK: - Authorization
    
    /// Request authorization to access the Photos library
    func requestAuthorization() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        
        switch status {
        case .authorized, .limited:
            isAuthorized = true
        case .denied, .restricted:
            throw PhotoLibraryError.accessDenied
        case .notDetermined:
            throw PhotoLibraryError.notDetermined
        @unknown default:
            throw PhotoLibraryError.unknown
        }
    }
    
    /// Check current authorization status
    func checkAuthorization() -> PHAuthorizationStatus {
        return PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }
    
    // MARK: - Fetching Photos
    
    /// Fetch photos created after a given date
    /// - Parameter since: Only return photos created after this date
    /// - Returns: Array of photo metadata
    func fetchPhotos(since: Date?) async throws -> [PhotoMetadata] {
        try await ensureAuthorized()
        
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        
        if let sinceDate = since {
            fetchOptions.predicate = NSPredicate(format: "creationDate > %@", sinceDate as NSDate)
        }
        
        // Fetch all asset types (images, videos, audio)
        let assets = PHAsset.fetchAssets(with: fetchOptions)
        
        var photos: [PhotoMetadata] = []
        assets.enumerateObjects { asset, _, _ in
            photos.append(PhotoMetadata(from: asset))
        }
        
        return photos
    }
    
    /// Fetch a single photo by its local identifier
    /// - Parameter id: The local identifier of the photo
    /// - Returns: Photo metadata if found
    func fetchPhoto(id: String) async throws -> PhotoMetadata? {
        try await ensureAuthorized()
        
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = result.firstObject else {
            return nil
        }
        
        return PhotoMetadata(from: asset)
    }
    
    /// Get the PHAsset for a given identifier
    func getAsset(id: String) async throws -> PHAsset? {
        try await ensureAuthorized()
        return PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }
    
    /// Export the original data for an asset
    /// - Parameter asset: The PHAsset to export
    /// - Returns: Tuple of (data, filename, UTI type)
    func exportAssetData(asset: PHAsset) async throws -> (Data, String, String) {
        try await ensureAuthorized()
        
        return try await withCheckedThrowingContinuation { continuation in
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            
            let resources = PHAssetResource.assetResources(for: asset)
            
            // Find the primary resource (original photo/video)
            guard let resource = resources.first(where: { 
                $0.type == .photo || $0.type == .video || $0.type == .fullSizePhoto || $0.type == .fullSizeVideo
            }) ?? resources.first else {
                continuation.resume(throwing: PhotoLibraryError.noResourceFound)
                return
            }
            
            var data = Data()
            let manager = PHAssetResourceManager.default()
            
            manager.requestData(for: resource, options: options) { chunk in
                data.append(chunk)
            } completionHandler: { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    let filename = resource.originalFilename
                    let uti = resource.uniformTypeIdentifier
                    continuation.resume(returning: (data, filename, uti))
                }
            }
        }
    }
    
    /// Export Live Photo components
    func exportLivePhotoData(asset: PHAsset) async throws -> LivePhotoData {
        try await ensureAuthorized()
        
        let resources = PHAssetResource.assetResources(for: asset)
        
        var photoData: Data?
        var videoData: Data?
        var photoFilename = "photo.heic"
        var videoFilename = "video.mov"
        
        for resource in resources {
            let data = try await exportResourceData(resource: resource)
            
            switch resource.type {
            case .photo, .fullSizePhoto:
                photoData = data
                photoFilename = resource.originalFilename
            case .pairedVideo, .fullSizePairedVideo:
                videoData = data
                videoFilename = resource.originalFilename
            default:
                break
            }
        }
        
        guard let photo = photoData else {
            throw PhotoLibraryError.noResourceFound
        }
        
        return LivePhotoData(
            photoData: photo,
            videoData: videoData,
            photoFilename: photoFilename,
            videoFilename: videoFilename
        )
    }
    
    private func exportResourceData(resource: PHAssetResource) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            var data = Data()
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            
            PHAssetResourceManager.default().requestData(for: resource, options: options) { chunk in
                data.append(chunk)
            } completionHandler: { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
    }
    
    private func ensureAuthorized() async throws {
        let status = checkAuthorization()
        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            try await requestAuthorization()
        default:
            throw PhotoLibraryError.accessDenied
        }
    }
}

// MARK: - Data Models

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
    let location: LocationData?
    
    init(from asset: PHAsset) {
        self.id = asset.localIdentifier
        self.creationDate = asset.creationDate
        self.modificationDate = asset.modificationDate
        self.pixelWidth = asset.pixelWidth
        self.pixelHeight = asset.pixelHeight
        self.duration = asset.duration
        self.isFavorite = asset.isFavorite
        self.isHidden = asset.isHidden
        
        // Map media type
        switch asset.mediaType {
        case .image:
            self.mediaType = "image"
        case .video:
            self.mediaType = "video"
        case .audio:
            self.mediaType = "audio"
        default:
            self.mediaType = "unknown"
        }
        
        // Map media subtypes
        var subtypes: [String] = []
        if asset.mediaSubtypes.contains(.photoLive) {
            subtypes.append("livePhoto")
        }
        if asset.mediaSubtypes.contains(.photoHDR) {
            subtypes.append("hdr")
        }
        if asset.mediaSubtypes.contains(.photoPanorama) {
            subtypes.append("panorama")
        }
        if asset.mediaSubtypes.contains(.photoScreenshot) {
            subtypes.append("screenshot")
        }
        if asset.mediaSubtypes.contains(.photoDepthEffect) {
            subtypes.append("depthEffect")
        }
        if asset.mediaSubtypes.contains(.videoHighFrameRate) {
            subtypes.append("highFrameRate")
        }
        if asset.mediaSubtypes.contains(.videoTimelapse) {
            subtypes.append("timelapse")
        }
        self.mediaSubtypes = subtypes
        
        // Location data
        if let location = asset.location {
            self.location = LocationData(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.altitude
            )
        } else {
            self.location = nil
        }
    }
}

struct LocationData: Content {
    let latitude: Double
    let longitude: Double
    let altitude: Double
}

struct LivePhotoData {
    let photoData: Data
    let videoData: Data?
    let photoFilename: String
    let videoFilename: String
}

// MARK: - Errors

enum PhotoLibraryError: Error, AbortError {
    case accessDenied
    case notDetermined
    case noResourceFound
    case unknown
    
    var status: HTTPResponseStatus {
        switch self {
        case .accessDenied:
            return .forbidden
        case .notDetermined:
            return .serviceUnavailable
        case .noResourceFound:
            return .notFound
        case .unknown:
            return .internalServerError
        }
    }
    
    var reason: String {
        switch self {
        case .accessDenied:
            return "Photos library access denied. Please grant permission in System Preferences."
        case .notDetermined:
            return "Photos library access not yet determined."
        case .noResourceFound:
            return "No exportable resource found for this asset."
        case .unknown:
            return "Unknown Photos library error."
        }
    }
}

