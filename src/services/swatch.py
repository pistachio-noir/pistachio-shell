#!/usr/bin/env python3
"""Writes a 64 px square of one colour as a PNG, for the colour picker's notification (Screenshots).

  swatch.py '#9fd88a' /run/user/1000/pistachio-colour.png
"""

import struct
import sys
import zlib


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


colour = bytes.fromhex(sys.argv[1].lstrip("#")[:6])
rows = b"".join(b"\0" + colour * 64 for _ in range(64))
with open(sys.argv[2], "wb") as f:
    f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 64, 64, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))
