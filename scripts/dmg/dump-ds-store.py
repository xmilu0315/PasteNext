#!/usr/bin/env python3
"""Extracts the icon positions from a .DS_Store into a small JSON file.

Used by scripts/dmg/verify-layout.swift to render a proof of the DMG window.

Usage: python3 scripts/dmg/dump-ds-store.py <volume-dir>   (prints JSON)
"""
import json
import os
import struct
import sys

VOLUME = sys.argv[1] if len(sys.argv) > 1 else "."
DS = os.path.join(VOLUME, ".DS_Store")

icons = []
if os.path.exists(DS):
    data = open(DS, "rb").read()
    i = 0
    while True:
        i = data.find(b"Iloc", i)
        if i < 0:
            break
        length = struct.unpack(">I", data[i + 4:i + 8])[0]
        blob = data[i + 8:i + 8 + length]
        if len(blob) >= 20:
            x = struct.unpack(">I", blob[4:8])[0]
            y = struct.unpack(">I", blob[8:12])[0]
            # The file name is stored as a UTF-16 string just before the record.
            name = ""
            j = i - 2
            # walk back to the length-prefixed UTF-16 name
            k = i - 4
            while k >= 0 and data[k] == 0:
                k -= 2
            if k >= 0:
                chars = []
                p = k
                while p >= 0 and data[p] != 0:
                    chars.append(chr(data[p]))
                    p -= 1
                name = "".join(reversed(chars))
            icons.append({"name": name or "item", "x": x, "y": y})
        i += 4

print(json.dumps({"icons": icons}))
