import XCTVapor
import Crypto
@testable import App

final class PhotoControllerTests: XCTestCase {
    var app: Application!
    let testSecret = "test-secret-key-for-testing"
    
    override func setUp() async throws {
        app = try await Application.make(.testing)
        try await configure(app)
        app.storage[SharedSecretKey.self] = testSecret
    }
    
    override func tearDown() async throws {
        try? await app.asyncShutdown()
    }
    
    // MARK: - Health Check Tests
    
    func testHealthCheckReturnsOK() async throws {
        try await app.test(.GET, "health") { res async in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "OK")
        }
    }
    
    func testHealthCheckDoesNotRequireAuth() async throws {
        // No auth headers, should still work
        try await app.test(.GET, "health") { res async in
            XCTAssertEqual(res.status, .ok)
        }
    }
    
    // MARK: - Photos List Tests
    
    func testPhotosListRequiresAuth() async throws {
        try await app.test(.GET, "photos") { res async in
            XCTAssertEqual(res.status, .unauthorized)
        }
    }
    
    func testPhotosListWithAuth() async throws {
        let (timestamp, signature) = generateAuthHeaders(method: "GET", path: "/photos")
        
        try await app.test(.GET, "photos", beforeRequest: { req in
            req.headers.add(name: "X-Timestamp", value: timestamp)
            req.headers.add(name: "X-Signature", value: signature)
        }) { res async in
            // May return .forbidden if Photos access not granted in test environment
            // or .ok if access is granted
            XCTAssertTrue([.ok, .forbidden, .serviceUnavailable].contains(res.status))
            
            if res.status == .ok {
                // Verify response structure
                let data = try? res.content.decode(PhotoListResponse.self)
                XCTAssertNotNil(data)
            }
        }
    }
    
    func testPhotosListWithSinceParameter() async throws {
        let sinceTimestamp = Date().timeIntervalSince1970 - 86400 // 24 hours ago
        // Note: Signature is computed on path only, not including query string
        let (timestamp, signature) = generateAuthHeaders(method: "GET", path: "/photos")
        
        try await app.test(.GET, "photos?since=\(sinceTimestamp)", beforeRequest: { req in
            req.headers.add(name: "X-Timestamp", value: timestamp)
            req.headers.add(name: "X-Signature", value: signature)
        }) { res async in
            XCTAssertTrue([.ok, .forbidden, .serviceUnavailable].contains(res.status))
        }
    }
    
    // MARK: - Photo Metadata Tests
    
    func testPhotoMetadataRequiresAuth() async throws {
        try await app.test(.GET, "photos/test-id") { res async in
            XCTAssertEqual(res.status, .unauthorized)
        }
    }
    
    func testPhotoMetadataWithInvalidId() async throws {
        let path = "/photos/nonexistent-id"
        let (timestamp, signature) = generateAuthHeaders(method: "GET", path: path)
        
        try await app.test(.GET, "photos/nonexistent-id", beforeRequest: { req in
            req.headers.add(name: "X-Timestamp", value: timestamp)
            req.headers.add(name: "X-Signature", value: signature)
        }) { res async in
            // Should be notFound or forbidden (if no Photos access)
            XCTAssertTrue([.notFound, .forbidden, .serviceUnavailable].contains(res.status))
        }
    }
    
    // MARK: - Photo Download Tests
    
    func testPhotoDownloadRequiresAuth() async throws {
        try await app.test(.GET, "photos/test-id/download") { res async in
            XCTAssertEqual(res.status, .unauthorized)
        }
    }
    
    func testPhotoDownloadWithInvalidId() async throws {
        let path = "/photos/nonexistent-id/download"
        let (timestamp, signature) = generateAuthHeaders(method: "GET", path: path)
        
        try await app.test(.GET, "photos/nonexistent-id/download", beforeRequest: { req in
            req.headers.add(name: "X-Timestamp", value: timestamp)
            req.headers.add(name: "X-Signature", value: signature)
        }) { res async in
            XCTAssertTrue([.notFound, .forbidden, .serviceUnavailable].contains(res.status))
        }
    }
    
    // MARK: - Live Photo Tests
    
    func testLivePhotoDownloadRequiresAuth() async throws {
        try await app.test(.GET, "photos/test-id/livephoto") { res async in
            XCTAssertEqual(res.status, .unauthorized)
        }
    }
    
    func testLivePhotoDownloadWithInvalidId() async throws {
        let path = "/photos/nonexistent-id/livephoto"
        let (timestamp, signature) = generateAuthHeaders(method: "GET", path: path)
        
        try await app.test(.GET, "photos/nonexistent-id/livephoto", beforeRequest: { req in
            req.headers.add(name: "X-Timestamp", value: timestamp)
            req.headers.add(name: "X-Signature", value: signature)
        }) { res async in
            XCTAssertTrue([.notFound, .forbidden, .serviceUnavailable, .badRequest].contains(res.status))
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateAuthHeaders(method: String, path: String) -> (timestamp: String, signature: String) {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let message = "\(method):\(path):\(timestamp)"
        let key = SymmetricKey(data: Data(testSecret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        let signatureHex = signature.map { String(format: "%02x", $0) }.joined()
        return (timestamp, signatureHex)
    }
}

// Response model for decoding
struct PhotoListResponse: Content {
    let count: Int
    let photos: [PhotoMetadata]
}

