# T440p Libreboot Builder

*(Українська інструкція: [README.uk.md](README.uk.md))*

Automated build tool for a [Libreboot](https://libreboot.org) firmware image
for the **Lenovo ThinkPad T440p**. It builds and verifies a ROM. It never
writes to SPI flash — flashing is a deliberate, separate, manual step you
do yourself after inspecting the output.

## 1. What this does, in order

1. Checks your OS/architecture and dependencies.
2. Verifies the 4 BIOS dump files you provide (size, duplicate-read hash
   match, structural sanity).
3. Merges the verified dumps and checks the T440p flash layout.
4. Clones the real `lbmk` (libreboot build system) and builds the T440p
   coreboot/GRUB2 target.
5. Installs your custom GRUB background and config options.
6. Verifies the finished ROM (size, CBFS contents, Intel Flash Descriptor,
   not blank) and splits it into the two chip-sized images you actually
   flash.
7. Writes `output/BUILD-REPORT.txt` and stops — it does not flash anything.

Any failed check aborts the whole run. This tool would rather stop than
hand you a ROM it isn't sure about.

## 2. Supported systems

Ubuntu LTS or Debian (stable/testing), x86_64, Bash 5+, Python 3.
`./build.sh` checks this itself and refuses to run anywhere else.

## 3. Installing dependencies

This tool never runs `apt install` for you — it only prints the exact
command. Run:

```
./build.sh --check
```

It will print two blocks of packages if anything is missing:

- **Wrapper-script dependencies** (git, python3, sha256sum, etc.) — install
  with the plain `apt-get install` line it prints.
- **libreboot build dependencies** — this tool reads them directly out of
  the cloned `lbmk` repo's own `config/dependencies/debian` (or `ubuntu`)
  file, so you get exactly what the real build needs, and prints the exact
  `sudo apt-get install --no-install-recommends ...` command lbmk itself
  would run internally via `./mk dependencies debian`.

## 4. Where to put your BIOS dumps

The T440p has **two physical SPI flash chips**: an 8 MiB chip under the
base cover (low address range, contains the Intel Flash Descriptor) and a
4 MiB chip under the small door (high address range). Libreboot's own SPI
guide recommends reading each chip **twice** and comparing hashes, to catch
a bad programmer connection — that's exactly what this tool checks.

Put four files in `dumps/`:

```
dumps/upper_1.bin   4 MiB (4194304 bytes)  -- door chip, read #1
dumps/upper_2.bin   4 MiB (4194304 bytes)  -- door chip, read #2
dumps/lower_1.bin   8 MiB (8388608 bytes)  -- base-cover chip, read #1
dumps/lower_2.bin   8 MiB (8388608 bytes)  -- base-cover chip, read #2
```

`upper_1` must be byte-identical to `upper_2`, and `lower_1` byte-identical
to `lower_2`. If they don't match, the tool stops and tells you which pair
disagreed — re-read that chip.

`dumps/` is never written to or modified by this tool. Everything it does
happens on copies under `work/`.

## 5. What the double-dump check actually proves

SHA256 matching between two reads only proves the two reads are identical
to *each other* — it says nothing about whether either one is a sane BIOS
image (both could, in principle, be a consistent bad read). After the hash
check, `tools/verify_dump.py` additionally checks that the data isn't
blank/degenerate (not >99% a single repeated byte, has a broad byte-value
histogram) and, for the LOWER dump, that a valid Intel Flash Descriptor
signature is present at the expected offset.

## 6. Adding a GRUB background

Put a PNG or JPEG in `assets/grub-background.png` (any name is fine — the
path is set by `GRUB_BACKGROUND` in `config/t440p.conf`). The tool
letterboxes/converts it to exactly 1280x800, 8-bit palette PNG — the exact
format and resolution libreboot's own default background ships as — and
installs it into the cloned build tree before building. It then confirms
with `cbfstool` that `background.png` actually landed inside the built
ROM's CBFS.

## 7. Dry run

```
./build.sh --check
```

Verifies OS, dependencies, dumps (sizes/hashes/structure), clones and
checks out libreboot source, confirms the T440p build target still exists,
and validates/converts the background image. Creates nothing in `output/`.

## 8. Full build

```
./build.sh --auto
```

or just `./build.sh` with no arguments (same thing, after printing the menu
banner). First run compiles a full coreboot cross-toolchain and can take a
long time and a lot of disk space — this is normal for any coreboot/
libreboot build, on any machine.

## 9. Where the ROM ends up

```
output/t440p-libreboot.rom              12 MiB, full image (reference/hash)
output/t440p-libreboot-spi1-8mb.rom     flash into the 8 MiB base-cover chip
output/t440p-libreboot-spi2-4mb.rom     flash into the 4 MiB door chip
output/*.sha256                         checksum for each file above
output/BUILD-REPORT.txt                 full report (see spec sections 23/29)
```

## 10. Verifying SHA256

```
cd output
sha256sum -c t440p-libreboot.rom.sha256
sha256sum -c t440p-libreboot-spi1-8mb.rom.sha256
sha256sum -c t440p-libreboot-spi2-4mb.rom.sha256
```

## 11. If something fails

The tool prints a colored `[ ERROR ]` block explaining exactly which check
failed and why, and the full run is logged to `logs/build-<timestamp>.log`.
It never prints "BUILD SUCCESSFUL" unless every check passed. Common
causes: mismatched dump pair (bad SPI read — re-dump that chip), wrong
dump size (wrong chip, or truncated read), missing dependencies (see
section 3), or a genuine build failure inside lbmk/coreboot (check the log
— the underlying error is usually in the last ~20 lines of build output).

## 12. Flashing (out of scope, on purpose)

This tool only produces and verifies `output/*.rom`. It never calls
`flashrom`/`flashprog` to write anything. Flashing an internal firmware
image onto a laptop mainboard carries real risk of turning it into a
brick if done wrong — verify the ROM yourself (section 10), then follow
libreboot's own external-programmer flashing guide for the T440p to write
`t440p-libreboot-spi1-8mb.rom` and `t440p-libreboot-spi2-4mb.rom` to their
respective chips.

---

## Grounded in real Libreboot source (why this tool is designed this way)

The original specification for this tool assumed a couple of things about
Libreboot that turned out not to match reality once checked against the
actual `lbmk` source and coreboot's own documentation for this board. This
tool implements the real mechanisms, not the assumed ones:

- **Wi-Fi whitelist.** There is no `./mk` command, build flag, or binary
  patch anywhere in `lbmk` that "removes" the Lenovo Wi-Fi whitelist,
  because the whitelist is code inside Lenovo's proprietary BIOS —
  libreboot replaces that firmware entirely, so the code simply isn't
  there. `lib/whitelist.sh` verifies the built ROM is a genuine coreboot
  image (and therefore inherently free of that code) instead of
  simulating a "patch" that doesn't exist upstream.
- **Vendor ME/GbE/descriptor files.** `lbmk` ships a redistributable
  Intel Flash Descriptor + GbE template for this board
  (`config/ifd/t440p/{ifd,gbe}`) and downloads Intel ME directly from
  Lenovo's own official update server at build time
  (`config/vendor/haswell/pkg.cfg`, hash-pinned in that file). A plain
  `./mk -b coreboot t440plibremrc_12mb` therefore already produces a
  complete, flashable ROM. Your dumps are used to preserve your **own
  original GbE MAC address** in the output (`lib/libreboot.sh
  inject_original_mac`, mirroring `lbmk`'s own documented
  `nvmutil`+`ifdtool` mechanism) — a personalization, not a build
  requirement.
- **Flash layout.** T440p has two physically different chips (8 MiB low /
  4 MiB high), confirmed against `doc.coreboot.org/mainboard/lenovo/
  t440p.html` and libreboot's own T440p install guide, which splits a
  combined image the same way this tool does
  (`dd bs=1M count=8` / `dd bs=1M skip=8`).
- **Build target names** (`t440plibremrc_12mb`,
  `t440plibremrc_4mcbfs_12mb`) and every `./mk` invocation in this project
  were read directly out of the cloned repo's `include/*.sh` and
  `config/coreboot/` — not guessed from documentation prose. `./mk -b
  coreboot list` (literally `ls -1 config/coreboot` inside `lbmk`) is used
  at runtime to confirm the target still exists rather than trusting a
  hardcoded string.

Sources: `libreboot.org/docs/install/t440p_external.html`,
`libreboot.org/docs/install/spi.html`, `libreboot.org/docs/build/`,
`doc.coreboot.org/mainboard/lenovo/t440p.html`, and the `lbmk` source
itself at `codeberg.org/libreboot/lbmk`.
