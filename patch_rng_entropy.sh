#!/usr/bin/env bash
# Mix a live hardware counter into the Digitakt II pseudo-random generator.
#
# The LCG at 0x401521C4 is never seeded: its state word at 0x4099D688 has
# exactly one referencing site, inside the generator itself, and there is no
# srand. The draw sequence is therefore identical on every boot, which makes
# the boot-intro selector deterministic.
#
# This replaces the generator's constant additive term with a read of DTIM0's
# free-running 32-bit counter, so every draw mixes in live time:
#
#   0x401521D4  addi.l #12345,%d0      06 80 00 00 30 39
#            -> add.l  0xFC07000C,%d0  D0 B9 FC 07 00 0C   (same 6 bytes)
#
# 0xFC07000C is DTIM0's DTCN. MAIN already reads it with move.l from four
# sites including early boot, so a 32-bit access there is known-good.
#
# Caveats, both stated rather than assumed:
#   - No section writes DTIM0's control registers, so its enablement is not
#     proved statically. If it is not running the counter reads constant, the
#     intro stays deterministic and nothing else changes.
#   - This affects every consumer of the generator, not only the intro.
#
# usage: ./patch_rng_entropy.sh section3_unpacked.bin [-o out.bin]
set -euo pipefail

SRC=${1:?usage: $0 <section3_unpacked.bin> [-o out.bin]}
OUT=$SRC
[ "${2:-}" = "-o" ] && OUT=${3:?missing output path}
[ "$OUT" != "$SRC" ] && cp -- "$SRC" "$OUT"

OFF=0x151DD4          # file offset of 0x401521D4
CUR=068000003039      # addi.l #12345,%d0
NEW=D0B9FC07000C      # add.l  0xFC07000C,%d0

get6() { dd if="$1" bs=1 skip=$(($2)) count=6 2>/dev/null | od -An -tx1 | tr -d ' \n' | tr a-f A-F; }

got=$(get6 "$OUT" "$OFF")
if [ "$got" = "$NEW" ]; then
  echo "already patched ($OFF)"
else
  [ "$got" = "$CUR" ] || { echo "ABORT: $OFF expected $CUR, found $got" >&2; exit 1; }
  printf "$(echo "$NEW" | sed 's/../\\x&/g')" |
    dd of="$OUT" bs=1 seek=$(($OFF)) conv=notrunc status=none
  echo "  $OFF $CUR -> $NEW  (addi.l #12345 -> add.l DTIM0 DTCN)"
fi
[ "$(get6 "$OUT" "$OFF")" = "$NEW" ] || { echo "FAILED" >&2; exit 1; }
echo "OK - generator now mixes DTIM0's counter into every draw -> $OUT"
