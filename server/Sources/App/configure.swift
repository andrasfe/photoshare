import Vapor

public func configure(_ app: Application) async throws {
    // Load environment variables
    let sharedSecret = Environment.get("PHOTOSHARE_SECRET") ?? "development-secret-change-me"
    
    // Store shared secret in app storage for middleware access
    app.storage[SharedSecretKey.self] = sharedSecret
    
    // Configure server
    app.http.server.configuration.hostname = "0.0.0.0"
    app.http.server.configuration.port = 8080
    
    // Register routes
    try routes(app)
    
    app.logger.info("PhotoShare server configured on port 8080")
    app.logger.info("Using shared secret from \(Environment.get("PHOTOSHARE_SECRET") != nil ? "environment" : "default (CHANGE FOR PRODUCTION)")")
}

// Storage key for shared secret
struct SharedSecretKey: StorageKey {
    typealias Value = String
}

extension Application {
    var sharedSecret: String {
        get { storage[SharedSecretKey.self] ?? "" }
        set { storage[SharedSecretKey.self] = newValue }
    }
}

