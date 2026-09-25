#!/usr/bin/env bash
# Make the Digitakt II boot-intro variant picker uniform (5 x 20%).
#
# The selector at 0x400D18AE draws from a 15-bit LCG (0..32767) and walks a
# cascade of `cmpi.l #T,%d0` tests. Stock weights are 99.902% / 0.049% / 0.024%
# / rarer / rarest. Patching the four thresholds makes each variant ~20%.
#
#   T1 6553  -> P(A)          = 6554/32768 = 1/5
#   T2 8191  -> P(B | !A)     = 8192/32768 = 1/4
#   T3 10922 -> P(C | !A!B)   = 10923/32768 = 1/3
#   T4 16383 -> P(D | !A!B!C) = 16384/32768 = 1/2
#
# Operates on the DECOMPRESSED OS (section3_unpacked.bin), not a flashable file.
#
# usage: ./patch_equal_intro.sh section3_unpacked.bin [-o out.bin]
set -euo pipefail

SRC=${1:?usage: $0 <section3_unpacked.bin> [-o out.bin]}
OUT=$SRC
[ "${2:-}" = "-o" ] && OUT=${3:?missing output path}
[ "$OUT" != "$SRC" ] && cp -- "$SRC" "$OUT"

# offset      current      new      variant
PATCHES="
0x0D14C2 00007FDF 00001999 A_0x402A1624
0x0D14CE 00003FFE 00001FFF B_0x402A1664
0x0D14E2 00003FFE 00002AAA C_0x402A1654
0x0D1504 00000FFE 00003FFF D_0x402A1644
"

get4() { dd if="$1" bs=1 skip=$(($2)) count=4 2>/dev/null | od -An -tx1 | tr -d ' \n' | tr a-f A-F; }

echo "verifying $OUT ..."
while read -r off cur new name; do
  [ -z "$off" ] && continue
  got=$(get4 "$OUT" "$off")
  if [ "$got" = "$new" ]; then echo "  $off already patched ($name)"; continue; fi
  [ "$got" = "$cur" ] || { echo "ABORT: $off expected $cur, found $got" >&2; exit 1; }
done <<< "$PATCHES"

echo "patching ..."
while read -r off cur new name; do
  [ -z "$off" ] && continue
  [ "$(get4 "$OUT" "$off")" = "$new" ] && continue
  printf "$(echo "$new" | sed 's/../\\x&/g')" |
    dd of="$OUT" bs=1 seek=$(($off)) conv=notrunc status=none
  echo "  $off $cur -> $new  ($name)"
done <<< "$PATCHES"

echo "verifying result ..."
while read -r off cur new name; do
  [ -z "$off" ] && continue
  got=$(get4 "$OUT" "$off")
  [ "$got" = "$new" ] || { echo "FAILED at $off: $got" >&2; exit 1; }
done <<< "$PATCHES"
echo "OK - all 5 intro variants now ~20% each -> $OUT"
