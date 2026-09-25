#!/usr/bin/env python3
"""Decode an Elektron OS .syx into its raw firmware image.

Frame layout (128 bytes each), verified against Digitakt II OS 1.16:
  F0 00 20 3C <prod> 00 <cmd> 00 | ctr_hi ctr_lo | 14 x (msb + 7 data) | msb + 3 data | chk | F7
  cmd 0x7F/01 = start, 0x7E = data, 0x7F/02 = end.
  -> 101 payload bytes per data frame.
"""
import sys

def decode(path):
    d = open(path, 'rb').read()
    msgs, i = [], 0
    while i < len(d):
        j = d.index(b'\xF7', i)
        msgs.append(d[i:j+1])
        i = j + 1
    out = bytearray()
    prev = None
    for m in msgs:
        if m[6] != 0x7E:
            continue
        ctr = (m[8] << 7) | m[9]
        if prev is not None and ctr != prev + 1:
            print(f"warning: counter gap {prev} -> {ctr}", file=sys.stderr)
        prev = ctr
        p = m[10:-1]                      # 117 bytes
        # MSB byte is bit-6-first: bit (6-t) carries data byte t.
        for k in range(0, 112, 8):        # 14 full 8-in-7 groups
            g = p[k:k+8]
            for t, b in enumerate(g[1:]):
                out.append(b | (0x80 if (g[0] >> (6 - t)) & 1 else 0))
        msb = p[112]                      # partial group: msb + 3 data
        for t in range(3):
            out.append(p[113+t] | (0x80 if (msb >> (6 - t)) & 1 else 0))
        # p[116] is a trailing check byte, not payload
    return bytes(out)

if __name__ == '__main__':
    img = decode(sys.argv[1])
    open(sys.argv[2], 'wb').write(img)
    print(f"{len(img)} bytes -> {sys.argv[2]}")
