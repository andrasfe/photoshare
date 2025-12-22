import Vapor
import Crypto

/// HMAC-SHA256 authentication middleware
/// 
/// Expects headers:
/// - X-Timestamp: Unix timestamp (must be within 5 minutes of server time)
/// - X-Signature: HMAC-SHA256 signature of "{method}:{path}:{timestamp}"
struct HMACAuthMiddleware: AsyncMiddleware {
    /// Maximum allowed time difference between client and server (5 minutes)
    private let maxTimeDrift: TimeInterval = 300
    
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // Get required headers
        guard let timestampString = request.headers.first(name: "X-Timestamp"),
              let timestamp = Double(timestampString) else {
            throw Abort(.unauthorized, reason: "Missing or invalid X-Timestamp header")
        }
        
        guard let signature = request.headers.first(name: "X-Signature") else {
            throw Abort(.unauthorized, reason: "Missing X-Signature header")
        }
        
        // Validate timestamp is within acceptable range
        let now = Date().timeIntervalSince1970
        let timeDiff = abs(now - timestamp)
        
        if timeDiff > maxTimeDrift {
            request.logger.warning("Request timestamp too old: \(timeDiff)s drift")
            throw Abort(.unauthorized, reason: "Request timestamp expired")
        }
        
        // Get shared secret from app storage
        let sharedSecret = request.application.sharedSecret
        
        // Build the message to sign: "{method}:{path}:{timestamp}"
        let method = request.method.string
        let path = request.url.path
        let message = "\(method):\(path):\(timestampString)"
        
        // Calculate expected signature
        let key = SymmetricKey(data: Data(sharedSecret.utf8))
        let expectedSignature = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        let expectedSignatureHex = expectedSignature.map { String(format: "%02x", $0) }.joined()
        
        // Compare signatures (constant-time comparison)
        guard signature.lowercased() == expectedSignatureHex.lowercased() else {
            request.logger.warning("Invalid signature for request: \(method) \(path)")
            throw Abort(.unauthorized, reason: "Invalid signature")
        }
        
        request.logger.debug("HMAC authentication successful for \(method) \(path)")
        return try await next.respond(to: request)
    }
}

