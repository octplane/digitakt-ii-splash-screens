#!/usr/bin/env python3
"""Decompressor for Elektron FELE3 firmware sections (Digitakt II OS 1.16).

Transcribed from FUN_80005728 in section 4, the ColdFire loader. An
aPLib-family LZSS: a sentinel-bit tag stream, Elias-gamma offsets and match
lengths, a reuse-previous-offset case, and a >3328 length bonus.

Verified: every compressed section consumes 100% of its input stream.

  ./depack.py                 # unpack all sections of digitakt2_os1.16_image.bin
  ./depack.py image.bin       # ... of another decoded image
"""
import struct
import sys


def depack(src, start, stream_len):
    """Unpack one section. `start` is the file offset of its 8-byte header."""
    limit = start + 8 + stream_len
    pos = start + 8                 # the loader does `addq.l #8,a0`
    out = bytearray()
    bitbuf = 0                      # d1: shift register, sentinel in bit 0
    lastoff = 1                     # d3

    def getbit():
        nonlocal bitbuf, pos
        bitbuf = (bitbuf << 1) & 0xFFFFFFFF
        if (bitbuf & 0xFF) == 0:    # sentinel shifted out -> refill
            if pos >= limit:
                raise StopIteration
            b = src[pos]
            pos += 1
            bitbuf = ((b << 1) | 1) & 0xFFFFFFFF
        return (bitbuf >> 8) & 1

    def gamma():
        v = 1
        while True:
            v = (v << 1) + getbit()
            if getbit():            # continuation bit: 1 stops
                return v

    try:
        while True:
            if getbit():                        # 1 -> literal byte
                out.append(src[pos]); pos += 1
                continue
            g = gamma()
            if g != 2:                          # g == 2 reuses the last offset
                v = (g << 8) + src[pos]; pos += 1
                if v == 767:                    # end marker (see note below)
                    break
                lastoff = v - 767
            n = (getbit() << 1) | getbit()      # 2-bit short length
            if n == 0:
                n = gamma() + 2
            if lastoff > 3328:
                n += 1
            s = len(out) - lastoff
            for _ in range(n + 1):              # 1 + n bytes copied
                out.append(out[s]); s += 1
    except (StopIteration, IndexError):
        pass                                    # streams end by exhaustion
    return bytes(out), pos - start - 8

# Note: the 767 end marker is unreachable as encoded — it needs gamma == 2,
# which the loader diverts to the reuse-offset path first. Termination is by
# input exhaustion, which matches every section exactly.


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else 'digitakt2_os1.16_image.bin'
    img = open(path, 'rb').read()
    count = struct.unpack('>I', img[0x24:0x28])[0]
    for r in range(count):
        i, off, size, addr = struct.unpack('>IIII', img[0x28 + r*16: 0x38 + r*16])
        foff = off + 8                          # table holds flash offsets
        if size < 64:
            print(f"  id={i}: {size} bytes at 0x{foff:06x} (not compressed)")
            continue
        if i == 4:
            open('section4_loader.bin', 'wb').write(img[foff:foff+size])
            print(f"  id={i}: stored raw, {size} bytes -> section4_loader.bin")
            continue
        stream_len = struct.unpack('>I', img[foff:foff+4])[0]
        data, used = depack(img, foff, stream_len)
        name = f'section{i}_unpacked.bin'
        open(name, 'wb').write(data)
        print(f"  id={i}: {stream_len} -> {len(data)} bytes ({len(data)/stream_len:.2f}x), "
              f"consumed {used}/{stream_len}, load 0x{addr:08x} -> {name}")


if __name__ == '__main__':
    main()
