# Digitakt II splash screens

The Digitakt II picks its boot animation at random from **five** of them. You
have almost certainly only ever seen one.

This repository contains a 16 byte patch that makes all five appear, and the
scripts to apply it to a firmware image you already have.

It contains no Elektron firmware, artwork, fonts or code.

## Why you only see one

The firmware really does choose between five boot animations. A selector reads
a pseudo-random number and walks a cascade of comparisons, with nominal weights
of roughly 99.9% for the usual one and a few thousandths of a percent for the
other four.

Those weights never take effect, because the generator is **never seeded**. Its
state word is written from exactly one place in the whole image: the generator
itself. There is no `srand` and no other writer, so the sequence of numbers is
identical on every boot and the selector lands on the same animation every
time. The other four are unreachable on a given unit.

The patch fixes both halves of that: it equalises the weights, and it mixes a
live hardware counter into the generator so the draw actually varies.

See [TECHNICAL.md](TECHNICAL.md) for the addresses and the reasoning.

## What you need

- A Digitakt II OS `.syx` that you obtained yourself. None is included here.
- Python 3, standard library only.
- [elektron-firmware-tool](https://github.com/mischa85/elektron-firmware-tool)
  by [@mischa85](https://github.com/mischa85), MIT. It handles compression and
  the integrity trailer, which this repository deliberately does not reimplement.

```sh
git clone https://github.com/mischa85/elektron-firmware-tool
(cd elektron-firmware-tool && make)
```

A `flake.nix` is provided if you use Nix, but nothing here needs more than
python3 and a C compiler.

## Build

Put your `.syx` in this directory, then:

```sh
./build.sh Digitakt_II_OS1.16.syx out.syx
```

It decodes the SysEx transport, decompresses the sections, applies three
patches to the OS section, recompresses, recomputes the checksum and the HMAC
trailer, and verifies the result round trips. The pipeline is deterministic:
the same input gives the same output hash.

Every patch verifies the bytes it expects before writing, and refuses to run if
they do not match, so it will not silently corrupt a different firmware version.

## The three patches

| Script | Bytes | Effect |
|---|---|---|
| `patch_equal_intro.sh` | 8 | four selector thresholds, so all five are equiprobable |
| `patch_rng_entropy.sh` | 6 | the generator's constant additive term becomes a read of a free running hardware counter |
| `patch_burn_first_draw.sh` | 2 | discards the first draw, which the new entropy does not reach in time |

The third one is not optional. Without it you get four of the five, because the
entropy enters the generator's low bits while its output samples higher ones,
so the first draw after boot is still nearly fixed. That first draw is the one
that selects the common animation.

## Status

Tested on one instrument, on OS 1.16, by its owner. All five animations appear
across restarts.

Only the OS section is modified. The bootstrap and the updater are untouched,
so the documented recovery path (hold `[FUNC]` at power on, then `[TRIG 4]` for
OS UPGRADE over MIDI DIN) still runs original code.

That is an argument, not a guarantee. Flashing modified firmware is at your own
risk and can leave a device unusable. Verify the checksum output, keep the
original `.syx`, and understand the recovery path before you start.

## Licence

[MIT](LICENSE) for the code here. See [NOTICE.md](NOTICE.md) for what is
deliberately excluded and why.

Digitakt and Elektron are trademarks of their respective owners. This project
is independent and is not affiliated with or endorsed by Elektron.
