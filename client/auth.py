"""HMAC authentication for PhotoShare API."""

import hashlib
import hmac
import time
from typing import Dict


def generate_auth_headers(
    method: str,
    path: str,
    shared_secret: str,
) -> Dict[str, str]:
    """
    Generate HMAC-SHA256 authentication headers for a request.
    
    The signature is computed over: "{method}:{path}:{timestamp}"
    
    Args:
        method: HTTP method (GET, POST, etc.)
        path: Request path (e.g., /photos)
        shared_secret: The shared secret key
    
    Returns:
        Dictionary with X-Timestamp and X-Signature headers
    """
    # Current Unix timestamp
    timestamp = str(int(time.time()))
    
    # Build the message to sign
    message = f"{method}:{path}:{timestamp}"
    
    # Calculate HMAC-SHA256 signature
    signature = hmac.new(
        key=shared_secret.encode('utf-8'),
        msg=message.encode('utf-8'),
        digestmod=hashlib.sha256
    ).hexdigest()
    
    return {
        "X-Timestamp": timestamp,
        "X-Signature": signature,
    }


def verify_signature(
    method: str,
    path: str,
    timestamp: str,
    signature: str,
    shared_secret: str,
    max_age_seconds: int = 300,
) -> bool:
    """
    Verify an HMAC signature (useful for testing).
    
    Args:
        method: HTTP method
        path: Request path
        timestamp: Unix timestamp string
        signature: The signature to verify
        shared_secret: The shared secret key
        max_age_seconds: Maximum allowed age of the request
    
    Returns:
        True if signature is valid and timestamp is within allowed range
    """
    # Check timestamp age
    try:
        request_time = int(timestamp)
        current_time = int(time.time())
        if abs(current_time - request_time) > max_age_seconds:
            return False
    except ValueError:
        return False
    
    # Calculate expected signature
    message = f"{method}:{path}:{timestamp}"
    expected_signature = hmac.new(
        key=shared_secret.encode('utf-8'),
        msg=message.encode('utf-8'),
        digestmod=hashlib.sha256
    ).hexdigest()
    
    # Constant-time comparison
    return hmac.compare_digest(signature.lower(), expected_signature.lower())

