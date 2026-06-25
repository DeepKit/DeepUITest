"""ULID generation.

Monotonic ULID (Universally Unique Lexicographically Sortable Identifier).
26-character base32 string: 10-char timestamp + 16-char random.

Format: 01AN4Z07BY79KA1307SR9X4MV3
         ^^^^^^^^^^ ^^^^^^^^^^^^^^^^
         timestamp   randomness

Monotonic within the same millisecond by incrementing the random component.
"""

from __future__ import annotations

import os
import threading
import time

# Crockford's base32 encoding (no I, L, O, U to avoid confusion)
_BASE32_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
_BASE32_MAP = {c: i for i, c in enumerate(_BASE32_ALPHABET)}
_ENCODING_LENGTH = 26
_TIMESTAMP_LENGTH = 10
_RANDOM_LENGTH = 16

# Module-level state for monotonic guarantee
_last_timestamp: int = 0
_last_random: bytes = b""
_lock = threading.Lock()


def generate() -> str:
    """Generate a monotonic ULID string.

    Returns:
        26-character base32 ULID string.
    """
    global _last_timestamp, _last_random

    with _lock:
        timestamp = int(time.time() * 1000)
        random_bytes = os.urandom(10)

        # Monotonic: if same timestamp, increment random component
        if timestamp == _last_timestamp and random_bytes <= _last_random:
            # Increment the last byte(s)
            random_bytes = _increment_bytes(_last_random)

        _last_timestamp = timestamp
        _last_random = random_bytes

    return _encode_time(timestamp) + _encode_random(random_bytes)


def _encode_time(timestamp: int) -> str:
    """Encode a millisecond timestamp as 10-character base32."""
    chars = []
    for _ in range(_TIMESTAMP_LENGTH):
        chars.append(_BASE32_ALPHABET[timestamp % 32])
        timestamp //= 32
    return "".join(reversed(chars))


def _encode_random(random_bytes: bytes) -> str:
    """Encode 10 random bytes as 16-character base32."""
    # Convert 10 bytes (80 bits) to 16 base32 chars (80 bits)
    value = int.from_bytes(random_bytes, "big")
    chars = []
    for _ in range(_RANDOM_LENGTH):
        chars.append(_BASE32_ALPHABET[value % 32])
        value //= 32
    return "".join(reversed(chars))


def _increment_bytes(data: bytes) -> bytes:
    """Increment a byte string by 1 (big-endian)."""
    result = bytearray(data)
    for i in range(len(result) - 1, -1, -1):
        if result[i] < 255:
            result[i] += 1
            break
        result[i] = 0
    return bytes(result)


def is_valid(ulid: str) -> bool:
    """Check if a string is a valid ULID."""
    if len(ulid) != _ENCODING_LENGTH:
        return False
    return all(c in _BASE32_MAP for c in ulid)