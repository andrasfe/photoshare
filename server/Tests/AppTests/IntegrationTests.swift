import XCTVapor
import Crypto
@testable import App

/// Integration tests that test the full request/response cycle
final class IntegrationTests: XCTestCase {
    var app: Application!
    let testSecret = "integration-test-secret"
    
    override func setUp() async throws {
        app = try await Application.make(.testing)
        try await configure(app)
        app.storage[SharedSecretKey.self] = testSecret
    }
    
    override func tearDown() async throws {
        try? await app.asyncShutdown()
    }
    
    // MARK: - Full Flow Tests
    
    func testFullAuthenticationFlow() async throws {
        // Test that a properly authenticated request goes through the full middleware chain
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let message = "GET:/photos:\(timestamp)"
        let key = SymmetricKey(data: Data(testSecret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        let signatureHex = signature.map { String(format: "%02x", $0) }.joined()
        
        try await app.test(.GET, "photos", beforeRequest: { req in
            req.headers.add(name: "X-Timestamp", value: timestamp)
            req.headers.add(name: "X-Signature", value: signatureHex)
        }) { res async in
            // Authentication should pass, result depends on Photos access
            XCTAssertNotEqual(res.status, .unauthorized,
                "Request should not be unauthorized with valid credentials")
        }
    }
    
    func testRequestWithQueryParametersInSignature() async throws {
        // Note: Signature is computed on path only, query parameters are NOT included
        // This is because Vapor's request.url.path excludes query string
        let sinceTimestamp = "1700000000"
        let path = "/photos"  // Path only, no query string
        let timestamp = String(Int(Date().timeIntervalSince1970))
        
        let message = "GET:\(path):\(timestamp)"
        let key = SymmetricKey(data: Data(testSecret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        let signatureHex = signature.map { String(format: "%02x", $0) }.joined()
        
        try await app.test(.GET, "photos?since=\(sinceTimestamp)", beforeRequest: { req in
            req.headers.add(name: "X-Timestamp", value: timestamp)
            req.headers.add(name: "X-Signature", value: signatureHex)
        }) { res async in
            XCTAssertNotEqual(res.status, .unauthorized)
        }
    }
    
    func testPathWithSpecialCharacters() async throws {
        // Photo IDs can contain slashes and special characters
        let photoId = "ABC123/L0/001"
        let encodedId = photoId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? photoId
        let path = "/photos/\(encodedId)"
        let timestamp = String(Int(Date().timeIntervalSince1970))
        
        let message = "GET:\(path):\(timestamp)"
        let key = SymmetricKey(data: Data(testSecret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        let signatureHex = signature.map { String(format: "%02x", $0) }.joined()
        
        try await app.test(.GET, "photos/\(encodedId)", beforeRequest: { req in
            req.headers.add(name: "X-Timestamp", value: timestamp)
            req.headers.add(name: "X-Signature", value: signatureHex)
        }) { res async in
            // Should authenticate successfully, then return 404 or forbidden
            XCTAssertTrue([.notFound, .forbidden, .serviceUnavailable].contains(res.status))
        }
    }
    
    // MARK: - Concurrent Request Tests
    
    func testConcurrentRequests() async throws {
        // Test that multiple concurrent requests are handled correctly
        let iterations = 10
        
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    let timestamp = String(Int(Date().timeIntervalSince1970))
                    let message = "GET:/health:\(timestamp)"
                    
                    do {
                        try await self.app.test(.GET, "health") { res async in
                            XCTAssertEqual(res.status, .ok, "Request \(i) should succeed")
                        }
                    } catch {
                        XCTFail("Request \(i) threw error: \(error)")
                    }
                }
            }
        }
    }
    
    // MARK: - Error Response Format Tests
    
    func testUnauthorizedResponseFormat() async throws {
        try await app.test(.GET, "photos") { res async in
            XCTAssertEqual(res.status, .unauthorized)
            
            // Verify response is valid JSON with error information
            let contentType = res.headers.first(name: .contentType)
            XCTAssertTrue(contentType?.contains("application/json") ?? false)
        }
    }
    
    func testNotFoundResponseFormat() async throws {
        let path = "/photos/definitely-not-a-real-id-12345"
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let message = "GET:\(path):\(timestamp)"
        let key = SymmetricKey(data: Data(testSecret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        let signatureHex = signature.map { String(format: "%02x", $0) }.joined()
        
        try await app.test(.GET, "photos/definitely-not-a-real-id-12345", beforeRequest: { req in
            req.headers.add(name: "X-Timestamp", value: timestamp)
            req.headers.add(name: "X-Signature", value: signatureHex)
        }) { res async in
            if res.status == .notFound {
                let contentType = res.headers.first(name: .contentType)
                XCTAssertTrue(contentType?.contains("application/json") ?? false)
            }
        }
    }
    
    // MARK: - Configuration Tests
    
    func testServerConfigurationLoaded() async throws {
        // Verify the server configuration is properly loaded
        XCTAssertEqual(app.http.server.configuration.port, 8080)
        XCTAssertEqual(app.http.server.configuration.hostname, "0.0.0.0")
    }
    
    func testSharedSecretConfigured() async throws {
        // Verify shared secret is stored in app storage
        let secret = app.storage[SharedSecretKey.self]
        XCTAssertNotNil(secret)
        XCTAssertEqual(secret, testSecret)
    }
}

