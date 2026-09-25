#!/usr/bin/env bash
# Discard the intro selector's first random draw.
#
# The entropy added by patch_rng_entropy.sh enters the generator's LOW bits,
# but the generator's output samples bits 16..30. One multiply is needed to
# diffuse low-bit variation upward, so the FIRST draw after boot is still
# confined to a narrow band while every later draw is uniform.
#
# Variant A is decided by that first draw and so never comes up; B..E are
# decided by later draws and appear normally. Observed on hardware: four of
# five variants, never the first.
#
# Fix: turn the redundant sign-extend into a second generator call, so the
# first draw is discarded and the A test uses a well-mixed value.
#
#   0x400D18BE  mvsw %d0,%d0   71 40   ->   jsr %a3@   4E 93
#
# Safe because the generator ends with andi.l #32767,%d0, so its result is
# always 0..32767 and the sign-extension was already a no-op.
#
# usage: ./patch_burn_first_draw.sh <section3.bin> [-o out.bin]
set -euo pipefail

SRC=${1:?usage: $0 <section3.bin> [-o out.bin]}
OUT=$SRC
[ "${2:-}" = "-o" ] && OUT=${3:?missing output path}
[ "$OUT" != "$SRC" ] && cp -- "$SRC" "$OUT"

OFF=0x0D14BE; CUR=7140; NEW=4E93
get2() { dd if="$1" bs=1 skip=$(($2)) count=2 2>/dev/null | od -An -tx1 | tr -d ' \n' | tr a-f A-F; }

got=$(get2 "$OUT" "$OFF")
if [ "$got" = "$NEW" ]; then
  echo "already patched ($OFF)"
else
  [ "$got" = "$CUR" ] || { echo "ABORT: $OFF expected $CUR, found $got" >&2; exit 1; }
  printf "$(echo "$NEW" | sed 's/../\\x&/g')" | dd of="$OUT" bs=1 seek=$(($OFF)) conv=notrunc status=none
  echo "  $OFF $CUR -> $NEW  (mvsw d0,d0 -> jsr (a3), burning the first draw)"
fi
[ "$(get2 "$OUT" "$OFF")" = "$NEW" ] || { echo "FAILED" >&2; exit 1; }
echo "OK - first draw discarded, variant A now reachable -> $OUT"
