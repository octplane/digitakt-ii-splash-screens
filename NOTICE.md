# What this repository excludes, and why

The MIT licence covers the scripts and documentation written for this project.
It grants no rights in Elektron firmware or any content derived from it.

Deliberately **not** included, and excluded by `.gitignore` so they cannot be
added by accident:

- firmware images, original or modified (`*.syx`)
- anything decoded or decompressed from one (`*.bin`)
- Elektron's release notes, and text derived from them
- artwork, logos, fonts and asset sheets extracted from the firmware (`*.png`)
- asset inventories listing the firmware's internal layout

The repository history was started fresh for publication rather than carried
over from the working notes, so none of the above appears in earlier commits
either.

The `screenshots/` directory holds photographs of a physical instrument's
display, taken by the author, with all camera metadata stripped. These are
photographs of a running device, in the same sense as any product photo or
forum post, and are not assets extracted from the firmware. Extracted artwork
is excluded as described above and remains excluded.

What is included is original work: a decoder and a decompressor written from
observation, three byte patches, a build script, and documentation of the
mechanism. The documentation quotes short strings and addresses where they are
needed as evidence for a claim, which is factual compatibility information, not
a substitute for the firmware.

`elektron-firmware-tool` is a third-party MIT project and is referenced rather
than vendored. Clone and build it yourself; see the README.

If you believe something here crosses a line, please open an issue and it will
be removed.
