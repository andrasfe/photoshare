import Vapor

func routes(_ app: Application) throws {
    // Health check - no auth required
    app.get("health") { req -> String in
        return "OK"
    }
    
    // Protected routes with HMAC authentication
    let protected = app.grouped(HMACAuthMiddleware())
    
    // Register photo routes
    try protected.register(collection: PhotoController())
}

