import XCTVapor
import Crypto
@testable import App

final class HMACAuthMiddlewareTests: XCTestCase {
    var app: Application!
    let testSecret = "test-secret-key-for-testing"
    
    override func setUp() async throws {
        app = try await Application.make(.testing)
        app.storage[SharedSecretKey.self] = testSecret
        
        // Add a test route behind auth middleware
        let protected = app.grouped(HMACAuthMiddleware())
        protected.get("test") { req -> String in
            return "authenticated"
        }
    }
    
    override func tearDown() async throws {
        try? await app.asyncShutdown()
    }
    
    // MARK: - Missing Headers Tests
    
    func testRejectsRequestWithoutTimestamp() async throws {
        try await app.test(.GET, "test", beforeRequest: { req in
            req.headers.add(name: "X-Signature", value: "somesignature")
        }) { res async in
            XCTAssertEqual(res.status, .unauthorized)
            XCTAssertTrue(res.body.string.contains("X-Timestamp"))
        }
    }
    
    func testRejectsRequestWithoutSignature() async throws {
        try await app.test(.GET, "test", beforeRequest: { req in
            req.headers.add(name: "X-Timestamp", value: String(Int(Date().timeIntervalSince1970)))
        }) { res async in
            XCTAssertEqual(res.status, .unauthorized)
            XCTAssertTrue(res.body.string.contains("X-Signature"))
        }
    }
    
    func testRejectsRequestWithInvalidTimestamp() async throws {
        try await app.test(.GET, "test", beforeRequest: { req in
            req.headers.add(name: "X-Timestamp", value: "not-a-number")
            req.headers.add(name: "X-Signature", value: "somesignature")
        }) { res async in
            XCTAssertEqual(res.status, .unauthorized)
        }
    }
    
    // MARK: - Timestamp Validation Tests
    
    func testRejectsExpiredTimestamp() async throws {
        // Timestamp from 10 minutes ago
        let oldTimestamp = String(Int(Date().timeIntervalSince1970) - 600)
        let signature = generateSignature(method: "GET", path: "/test", timestamp: oldTimestamp)
        
        try await app.test(.GET, "test", beforeRequest: { req in
            req.headers.add(name: "X-Timestamp", value: oldTimestamp)
            req.headers.add(name: "X-Signature", value: signature)
        }) { res async in
            XCTAssertEqual(res.status, .unauthorized)
            XCTAssertTrue(res.body.string.contains("expired"))
        }
    }
    
    func testRejectsFutureTimestamp() async throws {
        // Timestamp from 10 minutes in the future
        let futureTimestamp = String(Int(Date().timeIntervalSince1970) + 600)
        let signature = generateSignature(method: "GET", path: "/test", timestamp: futureTimestamp)
        
        try await app.test(.GET, "test", beforeRequest: { req in
            req.headers.add(name: "X-Timestamp", value: futureTimestamp)
            req.headers.add(name: "X-Signature", value: signature)
        }) { res async in
            XCTAssertEqual(res.status, .unauthorized)
        }
    }
    
    func testAcceptsTimestampWithin5Minutes() async throws {
        // Timestamp from 2 minutes ago (within 5 minute window)
        let recentTimestamp = String(Int(Date().timeIntervalSince1970) - 120)
        let signature = generateSignature(method: "GET", path: "/test", timestamp: recentTimestamp)
        
        try await app.test(.GET, "test", beforeRequest: { req in
            req.headers.add(name: "X-Timestamp", value: recentTimestamp)
            req.headers.add(name: "X-Signature", value: signature)
        }) { res async in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "authenticated")
        }
    }
    
    // MARK: - Signature Validation Tests
    
    func testRejectsInvalidSignature() async throws {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        
        try await app.test(.GET, "test", beforeRequest: { req in
            req.headers.add(name: "X-Timestamp", value: timestamp)
            req.headers.add(name: "X-Signature", value: "invalid-signature")
        }) { res async in
            XCTAssertEqual(res.status, .unauthorized)
            XCTAssertTrue(res.body.string.contains("Invalid signature"))
        }
    }
    
    func testRejectsSignatureForWrongPath() async throws {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        // Sign for wrong path
        let signature = generateSignature(method: "GET", path: "/wrong-path", timestamp: timestamp)
        
        try await app.test(.GET, "test", beforeRequest: { req in
            req.headers.add(name: "X-Timestamp", value: timestamp)
            req.headers.add(name: "X-Signature", value: signature)
        }) { res async in
            XCTAssertEqual(res.status, .unauthorized)
        }
    }
    
    func testRejectsSignatureForWrongMethod() async throws {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        // Sign for wrong method
        let signature = generateSignature(method: "POST", path: "/test", timestamp: timestamp)
        
        try await app.test(.GET, "test", beforeRequest: { req in
            req.headers.add(name: "X-Timestamp", value: timestamp)
            req.headers.add(name: "X-Signature", value: signature)
        }) { res async in
            XCTAssertEqual(res.status, .unauthorized)
        }
    }
    
    func testAcceptsValidSignature() async throws {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let signature = generateSignature(method: "GET", path: "/test", timestamp: timestamp)
        
        try await app.test(.GET, "test", beforeRequest: { req in
            req.headers.add(name: "X-Timestamp", value: timestamp)
            req.headers.add(name: "X-Signature", value: signature)
        }) { res async in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "authenticated")
        }
    }
    
    func testSignatureIsCaseInsensitive() async throws {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let signature = generateSignature(method: "GET", path: "/test", timestamp: timestamp)
        
        // Test uppercase signature
        try await app.test(.GET, "test", beforeRequest: { req in
            req.headers.add(name: "X-Timestamp", value: timestamp)
            req.headers.add(name: "X-Signature", value: signature.uppercased())
        }) { res async in
            XCTAssertEqual(res.status, .ok)
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateSignature(method: String, path: String, timestamp: String) -> String {
        let message = "\(method):\(path):\(timestamp)"
        let key = SymmetricKey(data: Data(testSecret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return signature.map { String(format: "%02x", $0) }.joined()
    }
}

