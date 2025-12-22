import XCTVapor
@testable import App

final class AppTests: XCTestCase {
    func testHealthCheck() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try? await app.asyncShutdown() } }
        
        try await configure(app)
        
        try await app.test(.GET, "health") { res async in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "OK")
        }
    }
    
    func testUnauthorizedWithoutHeaders() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try? await app.asyncShutdown() } }
        
        try await configure(app)
        
        try await app.test(.GET, "photos") { res async in
            XCTAssertEqual(res.status, .unauthorized)
        }
    }
}

