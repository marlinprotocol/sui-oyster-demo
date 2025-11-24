#!/usr/bin/env python3
"""
SUI Price Oracle Enclave - Python Implementation

Fetches SUI prices from CoinGecko and signs them with secp256k1.
"""

import sys
import time
import hashlib
from pathlib import Path
from typing import Dict, Any

from flask import Flask, jsonify
import requests
import hashlib
from ecdsa import SigningKey, SECP256k1
from ecdsa.util import sigencode_string

# Initialize Flask app
app = Flask(__name__)

# Global state
signing_key: SigningKey = None
http_session = requests.Session()

# Intent scope constant (0 for personal intent)
INTENT_SCOPE = 0


def fetch_sui_price() -> float:
    """Fetch current SUI price from CoinGecko API."""
    url = "https://api.coingecko.com/api/v3/simple/price?ids=sui&vs_currencies=usd"
    
    try:
        response = http_session.get(url, timeout=10)
        response.raise_for_status()
        data = response.json()
        return data["sui"]["usd"]
    except Exception as e:
        app.logger.error(f"Failed to fetch SUI price: {e}")
        raise


def current_timestamp_ms() -> int:
    """Get current timestamp in milliseconds."""
    return int(time.time() * 1000)


def serialize_price_update_payload(price: int) -> bytes:
    """
    Serialize PriceUpdatePayload using BCS.
    
    Manual BCS encoding:
    - u64: 8-byte little-endian encoding
    """
    # PriceUpdatePayload { price: u64 }
    return price.to_bytes(8, 'little')


def serialize_intent_message(intent: int, timestamp_ms: int, payload_bytes: bytes) -> bytes:
    """
    Serialize IntentMessage<T> using BCS.
    
    Manual BCS encoding:
    - u8: 1-byte encoding
    - u64: 8-byte little-endian encoding
    - struct fields: concatenated in order
    """
    # IntentMessage { intent: u8, timestamp_ms: u64, data: T }
    result = bytearray()
    
    # intent: u8
    result.extend(bytes([intent]))
    
    # timestamp_ms: u64
    result.extend(timestamp_ms.to_bytes(8, 'little'))
    
    # data: T (already serialized payload bytes)
    result.extend(payload_bytes)
    
    return bytes(result)


def sign_price_data(private_key: SigningKey, price: int, timestamp_ms: int) -> str:
    """
    Sign price data following Nautilus pattern using secp256k1.
    
    Args:
        private_key: secp256k1 signing key
        price: Price in USD × 10^6 (u64)
        timestamp_ms: Unix timestamp in milliseconds (u64)
    
    Returns:
        Hex-encoded 64-byte signature
    """
    # Serialize payload
    payload_bytes = serialize_price_update_payload(price)
    
    # Serialize IntentMessage wrapper
    message_bytes = serialize_intent_message(INTENT_SCOPE, timestamp_ms, payload_bytes)
    
    # Hash with SHA256
    message_hash = hashlib.sha256(message_bytes).digest()
    
    # Sign with secp256k1 using deterministic nonce (RFC 6979)
    # sigencode_string returns raw (r, s) as 64 bytes which matches Rust/Node.js compact format
    signature = private_key.sign_digest_deterministic(
        message_hash, 
        hashfunc=hashlib.sha256,
        sigencode=sigencode_string
    )
    
    # Return hex-encoded signature (64 bytes compact format)
    return signature.hex()


def load_signing_key_from_file(path: Path) -> SigningKey:
    """Load secp256k1 signing key from file."""
    key_bytes = path.read_bytes()
    
    # secp256k1 private key is 32 bytes
    if len(key_bytes) != 32:
        raise ValueError(f"Expected 32-byte secp256k1 private key, got {len(key_bytes)} bytes")
    
    return SigningKey.from_string(key_bytes, curve=SECP256k1)


@app.route("/health", methods=["GET"])
def health_check():
    """Health check endpoint."""
    return jsonify({"status": "ok"})


@app.route("/public-key", methods=["GET"])
def get_public_key():
    """Get the enclave's secp256k1 public key (33 bytes compressed)."""
    verifying_key = signing_key.get_verifying_key()
    # Get compressed public key (33 bytes: 0x02/0x03 + x coordinate)
    pk_hex = verifying_key.to_string('compressed').hex()
    
    return jsonify({
        "public_key": pk_hex
    })


@app.route("/price", methods=["GET"])
def get_signed_price():
    """Get signed SUI price data."""
    try:
        # Fetch current SUI price from CoinGecko
        price_usd = fetch_sui_price()
        
        # Convert to u64 with 6 decimal places precision
        price = int(price_usd * 1_000_000)
        
        # Get timestamp in milliseconds
        timestamp_ms = current_timestamp_ms()
        
        app.logger.info(f"Fetched SUI price: ${price_usd:.6f} (raw: {price})")
        
        # Sign the data
        signature = sign_price_data(signing_key, price, timestamp_ms)
        
        return jsonify({
            "price": price,
            "timestamp_ms": timestamp_ms,
            "signature": signature
        })
    
    except Exception as e:
        app.logger.error(f"Failed to process price request: {e}")
        return jsonify({
            "error": "Failed to fetch or sign price",
            "message": str(e)
        }), 503


def main():
    """Main entry point."""
    global signing_key
    
    # Get key path from command line args
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path-to-signing-key>", file=sys.stderr)
        sys.exit(1)
    
    key_path = Path(sys.argv[1])
    
    print(f"Loading secp256k1 signing key from: {key_path}")
    signing_key = load_signing_key_from_file(key_path)
    print("Signing key loaded successfully")
    
    # Log public key for reference
    verifying_key = signing_key.get_verifying_key()
    pk_hex = verifying_key.to_string('compressed').hex()
    print(f"Public key (hex): {pk_hex}")
    
    # Start server
    host = "0.0.0.0"
    port = 3000
    
    print(f"Starting server on {host}:{port}")
    app.run(host=host, port=port, debug=False)


if __name__ == "__main__":
    main()
