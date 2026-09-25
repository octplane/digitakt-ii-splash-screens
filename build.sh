#!/usr/bin/env bash
# Build the modified Digitakt II firmware end to end, from the stock .syx.
#
#   ./build.sh [stock.syx] [out.syx]
#
# Stages, each verified:
#   1. decode the SysEx transport and decompress the sections
#   2. patch section 3 (MAIN OS):
#        - four selector thresholds  -> all five boot intros equiprobable
#        - generator additive term   -> mix in DTIM0's free-running counter
#        - discard the first draw    -> the entropy needs one multiply to reach
#                                       the output bits, so draw 1 is weak
#   3. recompress and rebuild, recomputing the checksum and the HMAC trailer
#   4. round-trip check: the rebuilt file's section 3 must match what we patched
set -euo pipefail
cd "$(dirname "$0")"

SRC=${1:-Digitakt_II_OS1.16.syx}
OUT=${2:-Digitakt_II_OS1.16_randomintro2.syx}
TOOL=./elektron-firmware-tool/elektron-firmware-tool

[ -f "$SRC" ]  || { echo "missing $SRC" >&2; exit 1; }
[ -x "$TOOL" ] || { echo "missing $TOOL; build it with: (cd elektron-firmware-tool && make)" >&2; exit 1; }

echo "1. decode + decompress"
./unsyx.py "$SRC" digitakt2_os1.16_image.bin >/dev/null
./depack.py digitakt2_os1.16_image.bin >/dev/null

echo "2. patch section 3"
cp section3_unpacked.bin section3_patched.bin
./patch_equal_intro.sh     section3_patched.bin | sed 's/^/     /'
./patch_rng_entropy.sh     section3_patched.bin | sed 's/^/     /'
./patch_burn_first_draw.sh section3_patched.bin | sed 's/^/     /'
echo "     $(cmp -l section3_unpacked.bin section3_patched.bin | wc -l | tr -d ' ') bytes changed from stock"

echo "3. rebuild"
$TOOL -i "$SRC" -c 3 section3_patched.bin -o "$OUT" 2>&1 | sed -n 's/^  /     /p'

echo "4. verify"
$TOOL -i "$OUT" 2>&1 | sed -n 's/^checksums/     checksums/p'
RT=$(mktemp -d); $TOOL -i "$OUT" -d 3 -o "$RT" >/dev/null 2>&1
cmp "$RT/section_3_MAIN_OS.bin" section3_patched.bin && echo "     section 3 round-trip: identical"
rm -rf "$RT"
echo
echo "built $OUT"
shasum -a 256 "$OUT"
