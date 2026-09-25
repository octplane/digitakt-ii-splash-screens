# How the splash selector works, and what the patch changes

Addresses are runtime addresses in the decompressed OS section, which loads at
`0x40000400`. Subtract that to get a file offset in `section3_unpacked.bin`.
Everything below was established on OS 1.16.

## Getting at the OS section

An OS `.syx` is a SysEx transport wrapping a container of compressed sections.
`unsyx.py` decodes the transport, `depack.py` decompresses the sections.

The transport carries 101 payload bytes per 128 byte frame in 8-in-7 bit
packing. Two details are easy to get wrong:

- **Frame size.** 98 bytes per frame silently drops 3 bytes at every frame
  boundary; 102 injects a junk byte. 101 is the only value that yields both
  intact strings and unbroken runs of zeros.
- **Bit order.** The MSB byte is bit-6-first: bit `(6-t)` carries data byte `t`,
  not bit `t`. Getting this backwards still produces perfectly readable ASCII,
  because text has every high bit clear, so strings cannot validate it. It
  corrupts roughly half the high bits everywhere else.

The codec is an LZ77 plus Elias-gamma scheme of the aPLib family. `depack.py`
implements decompression only. For the compression direction, and for the
container's checksum and HMAC trailer, this project uses
[elektron-firmware-tool](https://github.com/mischa85/elektron-firmware-tool)
rather than reimplementing them.

## The selector

At `0x400D18AE` a selector draws pseudo-random numbers and walks a cascade,
choosing one of five draw routines from a table at `0x402A1624`:

```
r1 = rand();  r1 <= 32735  ->  0x400D13AE     the usual animation
r2 = rand();  r2 <= 16382  ->  0x400D10A8
r3 = rand();  r3 <= 16382  ->  0x400D108C
r4 = rand();  r4 <=  4094  ->  0x400D1018
                     else  ->  0x400D0C6A     a dither path with its own artwork
```

Nominal weights, given a uniform draw over 0..32767:

| Routine | Weight | About 1 in |
|---|---|---|
| `0x400D13AE` | 99.902% | 1 |
| `0x400D10A8` | 0.0488% | 2,048 |
| `0x400D108C` | 0.0244% | 4,096 |
| `0x400D1018` | 0.0031% | 32,772 |
| `0x400D0C6A` | 0.0214% | 4,680 |

Note the last cascade threshold is much tighter than the two above it, so the
final `else` branch is more likely than the test immediately before it.

## The generator, and why the weights never mattered

`0x401521C4` is a textbook linear congruential generator using the constants
from the ANSI C reference `rand()`:

```
seed = seed * 1103515245 + 12345      (mod 2^32)
out  = (seed >> 16) & 0x7FFF          (0..32767)
```

Its state word lives at `0x4099D688`, and that address is referenced from
**exactly one site in the entire image**: the generator itself. There is no
seeding function and no other writer.

So the sequence is identical on every boot, the selector resolves to the same
routine every time, and the four low weight routines are unreachable in
practice. The percentages above describe what the cascade would do given a
random draw. The draw is not random.

## The patch

### 1. Equalise the weights, 8 bytes

Four `cmpi.l` immediates, chosen so each branch takes one fifth of what reaches
it:

| File offset | From | To | Gives |
|---|---|---|---|
| `0x0D14C2` | 32735 | 6553 | 1/5 |
| `0x0D14CE` | 16382 | 8191 | 1/4 of the rest |
| `0x0D14E2` | 16382 | 10922 | 1/3 of the rest |
| `0x0D1504` | 4094 | 16383 | 1/2 of the rest |

Result is 20.00% each, within 0.001%. The residual is integer rounding on a
32768 value range.

### 2. Give the generator real entropy, 6 bytes

Replace the constant additive term with a read of a free running 32 bit
hardware counter, in the same six bytes:

```
0x401521D4   addi.l #12345,%d0      06 80 00 00 30 39
          -> add.l  0xFC07000C,%d0  D0 B9 FC 07 00 0C
```

`0xFC07000C` is DMA Timer 0's counter on the MCF54415. Two reasons it is the
right choice:

- The OS already reads that address with `move.l` from four separate sites
  including early boot, so a 32 bit access there is known good rather than
  assumed.
- ColdFire has no `add.w <address>,Dn`, so a 16 bit source such as the PIT
  counter cannot be read in this form. A 32 bit read of a 16 bit register risks
  a bus error. DMA Timer 0's counter is genuinely 32 bits.

Note that nothing in any section writes that timer's control registers, so
where it is started is unknown. That it *is* running was established by the
patch working on hardware.

This affects every consumer of the generator, not only the splash selector.

### 3. Discard the first draw, 2 bytes

With only the first two patches you get four of the five animations, never the
common one. That is structural.

The entropy enters the generator's **low** bits, but the output samples bits
16..30. One multiply is needed to diffuse a low bit change upward, so the first
draw after boot is still confined to a narrow band while every later draw is
well mixed. The cascade decides the common routine on that first draw and the
others on later ones.

A Monte-Carlo over plausible counter jitter puts `P(draw1 <= 6553)` at 0.00% in
every regime tried, against about 20% for draw 2 and draw 3.

The fix reuses a redundant instruction:

```
0x400D18BE   mvsw %d0,%d0   71 40   ->   jsr %a3@   4E 93
```

The sign extend is a no-op, because the generator ends with
`andi.l #32767,%d0` and so always returns a positive 15 bit value. Turning it
into a second generator call discards the weak draw and tests the common
routine against a well mixed one. Same two bytes, no relocation, which matters
because there is no free space.

The general lesson: when injecting entropy into an LCG, inject where the output
samples. Adding to the low bits randomises everything except the very next draw.

## Verification

`build.sh` checks that the rebuilt file's OS section decompresses back to
exactly the bytes that were patched, and that the tool reports the checksums as
valid. Each patch script verifies the bytes it expects before writing.

Rebuilding from the same input reproduces the same output hash.
