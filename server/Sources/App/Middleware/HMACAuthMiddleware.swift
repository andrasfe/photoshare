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
    
    /// Expected signature length (SHA256 = 64 hex chars)
    private let expectedSignatureLength = 64
    
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // 1. Validate shared secret is configured and not default
        let sharedSecret = request.application.sharedSecret
        guard !sharedSecret.isEmpty,
              sharedSecret != "development-secret-change-me" else {
            request.logger.error("SECURITY: Server has no valid shared secret configured")
            throw Abort(.internalServerError, reason: "Server configuration error")
        }
        
        // 2. Validate X-Timestamp header exists and is valid
        guard let timestampString = request.headers.first(name: "X-Timestamp") else {
            request.logger.warning("SECURITY: Missing X-Timestamp header from \(request.remoteAddress?.description ?? "unknown")")
            throw Abort(.unauthorized, reason: "Missing X-Timestamp header")
        }
        
        guard let timestamp = Double(timestampString) else {
            request.logger.warning("SECURITY: Invalid X-Timestamp format from \(request.remoteAddress?.description ?? "unknown")")
            throw Abort(.unauthorized, reason: "Invalid X-Timestamp header")
        }
        
        // 3. Validate X-Signature header exists and has correct format
        guard let signature = request.headers.first(name: "X-Signature") else {
            request.logger.warning("SECURITY: Missing X-Signature header from \(request.remoteAddress?.description ?? "unknown")")
            throw Abort(.unauthorized, reason: "Missing X-Signature header")
        }
        
        // Validate signature format (must be hex string of correct length)
        guard signature.count == expectedSignatureLength,
              signature.allSatisfy({ $0.isHexDigit }) else {
            request.logger.warning("SECURITY: Invalid signature format from \(request.remoteAddress?.description ?? "unknown")")
            throw Abort(.unauthorized, reason: "Invalid signature format")
        }
        
        // 4. Validate timestamp is within acceptable range (prevents replay attacks)
        let now = Date().timeIntervalSince1970
        let timeDiff = abs(now - timestamp)
        
        if timeDiff > maxTimeDrift {
            request.logger.warning("SECURITY: Expired timestamp (\(Int(timeDiff))s drift) from \(request.remoteAddress?.description ?? "unknown")")
            throw Abort(.unauthorized, reason: "Request timestamp expired")
        }
        
        // 5. Build and verify signature
        let method = request.method.string
        let path = request.url.path
        let message = "\(method):\(path):\(timestampString)"
        
        let key = SymmetricKey(data: Data(sharedSecret.utf8))
        let expectedMAC = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        
        // Convert provided signature to Data for constant-time comparison
        guard let providedSignatureData = Data(hexString: signature.lowercased()) else {
            request.logger.warning("SECURITY: Could not decode signature hex from \(request.remoteAddress?.description ?? "unknown")")
            throw Abort(.unauthorized, reason: "Invalid signature")
        }
        
        // Constant-time comparison to prevent timing attacks
        let expectedData = Data(expectedMAC)
        guard constantTimeCompare(expectedData, providedSignatureData) else {
            request.logger.warning("SECURITY: Signature mismatch for \(method) \(path) from \(request.remoteAddress?.description ?? "unknown")")
            throw Abort(.unauthorized, reason: "Invalid signature")
        }
        
        request.logger.debug("HMAC auth successful for \(method) \(path)")
        return try await next.respond(to: request)
    }
    
    /// Constant-time comparison to prevent timing attacks
    private func constantTimeCompare(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var result: UInt8 = 0
        for (x, y) in zip(a, b) {
            result |= x ^ y
        }
        return result == 0
    }
}

// MARK: - Data Hex Extension

extension Data {
    init?(hexString: String) {
        let len = hexString.count
        guard len % 2 == 0 else { return nil }
        
        var data = Data(capacity: len / 2)
        var index = hexString.startIndex
        
        for _ in 0..<(len / 2) {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }
        
        self = data
    }
}

