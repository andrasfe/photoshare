"""Unit tests for the auth module."""

import hashlib
import hmac
import time
from unittest.mock import patch

import pytest

from auth import generate_auth_headers, verify_signature


class TestGenerateAuthHeaders:
    """Tests for generate_auth_headers function."""
    
    def test_returns_required_headers(self):
        """Should return both X-Timestamp and X-Signature headers."""
        headers = generate_auth_headers("GET", "/photos", "secret")
        
        assert "X-Timestamp" in headers
        assert "X-Signature" in headers
    
    def test_timestamp_is_current(self):
        """Timestamp should be close to current time."""
        before = int(time.time())
        headers = generate_auth_headers("GET", "/photos", "secret")
        after = int(time.time())
        
        timestamp = int(headers["X-Timestamp"])
        assert before <= timestamp <= after
    
    def test_signature_format(self):
        """Signature should be a hex string."""
        headers = generate_auth_headers("GET", "/photos", "secret")
        
        signature = headers["X-Signature"]
        # SHA256 produces 64 hex characters
        assert len(signature) == 64
        assert all(c in "0123456789abcdef" for c in signature)
    
    def test_signature_is_deterministic_for_same_timestamp(self):
        """Same inputs should produce same signature."""
        with patch('auth.time.time', return_value=1700000000):
            headers1 = generate_auth_headers("GET", "/photos", "secret")
            headers2 = generate_auth_headers("GET", "/photos", "secret")
        
        assert headers1["X-Signature"] == headers2["X-Signature"]
    
    def test_signature_differs_for_different_methods(self):
        """Different methods should produce different signatures."""
        with patch('auth.time.time', return_value=1700000000):
            headers_get = generate_auth_headers("GET", "/photos", "secret")
            headers_post = generate_auth_headers("POST", "/photos", "secret")
        
        assert headers_get["X-Signature"] != headers_post["X-Signature"]
    
    def test_signature_differs_for_different_paths(self):
        """Different paths should produce different signatures."""
        with patch('auth.time.time', return_value=1700000000):
            headers1 = generate_auth_headers("GET", "/photos", "secret")
            headers2 = generate_auth_headers("GET", "/photos/123", "secret")
        
        assert headers1["X-Signature"] != headers2["X-Signature"]
    
    def test_signature_differs_for_different_secrets(self):
        """Different secrets should produce different signatures."""
        with patch('auth.time.time', return_value=1700000000):
            headers1 = generate_auth_headers("GET", "/photos", "secret1")
            headers2 = generate_auth_headers("GET", "/photos", "secret2")
        
        assert headers1["X-Signature"] != headers2["X-Signature"]
    
    def test_signature_matches_expected_format(self):
        """Verify signature matches HMAC-SHA256 of expected message."""
        secret = "test-secret"
        method = "GET"
        path = "/photos"
        
        with patch('auth.time.time', return_value=1700000000):
            headers = generate_auth_headers(method, path, secret)
        
        # Manually compute expected signature
        message = f"{method}:{path}:1700000000"
        expected = hmac.new(
            secret.encode('utf-8'),
            message.encode('utf-8'),
            hashlib.sha256
        ).hexdigest()
        
        assert headers["X-Signature"] == expected


class TestVerifySignature:
    """Tests for verify_signature function."""
    
    def test_accepts_valid_signature(self):
        """Should accept a valid signature."""
        secret = "test-secret"
        timestamp = str(int(time.time()))
        message = f"GET:/photos:{timestamp}"
        signature = hmac.new(
            secret.encode('utf-8'),
            message.encode('utf-8'),
            hashlib.sha256
        ).hexdigest()
        
        assert verify_signature("GET", "/photos", timestamp, signature, secret)
    
    def test_rejects_invalid_signature(self):
        """Should reject an invalid signature."""
        timestamp = str(int(time.time()))
        
        assert not verify_signature(
            "GET", "/photos", timestamp, "invalid-signature", "secret"
        )
    
    def test_rejects_expired_timestamp(self):
        """Should reject timestamps older than max_age_seconds."""
        secret = "test-secret"
        old_timestamp = str(int(time.time()) - 600)  # 10 minutes ago
        message = f"GET:/photos:{old_timestamp}"
        signature = hmac.new(
            secret.encode('utf-8'),
            message.encode('utf-8'),
            hashlib.sha256
        ).hexdigest()
        
        # Default max_age is 300 seconds (5 minutes)
        assert not verify_signature(
            "GET", "/photos", old_timestamp, signature, secret
        )
    
    def test_accepts_recent_timestamp(self):
        """Should accept timestamps within max_age_seconds."""
        secret = "test-secret"
        recent_timestamp = str(int(time.time()) - 120)  # 2 minutes ago
        message = f"GET:/photos:{recent_timestamp}"
        signature = hmac.new(
            secret.encode('utf-8'),
            message.encode('utf-8'),
            hashlib.sha256
        ).hexdigest()
        
        assert verify_signature(
            "GET", "/photos", recent_timestamp, signature, secret
        )
    
    def test_rejects_future_timestamp(self):
        """Should reject timestamps too far in the future."""
        secret = "test-secret"
        future_timestamp = str(int(time.time()) + 600)  # 10 minutes from now
        message = f"GET:/photos:{future_timestamp}"
        signature = hmac.new(
            secret.encode('utf-8'),
            message.encode('utf-8'),
            hashlib.sha256
        ).hexdigest()
        
        assert not verify_signature(
            "GET", "/photos", future_timestamp, signature, secret
        )
    
    def test_rejects_invalid_timestamp_format(self):
        """Should reject non-numeric timestamps."""
        assert not verify_signature(
            "GET", "/photos", "not-a-number", "signature", "secret"
        )
    
    def test_signature_comparison_is_case_insensitive(self):
        """Should accept signatures regardless of case."""
        secret = "test-secret"
        timestamp = str(int(time.time()))
        message = f"GET:/photos:{timestamp}"
        signature = hmac.new(
            secret.encode('utf-8'),
            message.encode('utf-8'),
            hashlib.sha256
        ).hexdigest()
        
        # Test uppercase
        assert verify_signature(
            "GET", "/photos", timestamp, signature.upper(), secret
        )
        
        # Test lowercase
        assert verify_signature(
            "GET", "/photos", timestamp, signature.lower(), secret
        )
    
    def test_custom_max_age(self):
        """Should respect custom max_age_seconds parameter."""
        secret = "test-secret"
        old_timestamp = str(int(time.time()) - 400)  # 6.7 minutes ago
        message = f"GET:/photos:{old_timestamp}"
        signature = hmac.new(
            secret.encode('utf-8'),
            message.encode('utf-8'),
            hashlib.sha256
        ).hexdigest()
        
        # Should fail with default 300 seconds
        assert not verify_signature(
            "GET", "/photos", old_timestamp, signature, secret,
            max_age_seconds=300
        )
        
        # Should pass with 600 seconds
        assert verify_signature(
            "GET", "/photos", old_timestamp, signature, secret,
            max_age_seconds=600
        )

