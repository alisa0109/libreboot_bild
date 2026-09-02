#!/usr/bin/env python3
"""Validate and convert a user-supplied GRUB background image.

lbmk ships its default background as a 1280x800, 8-bit palette PNG at
config/data/grub/background/background1280x800.png, and only ever embeds
that exact path/filename into CBFS (include/rom.sh add_grub()). To use a
custom background we therefore replace that file in the cloned tree with a
converted copy of the user's image, at the same exact resolution.

Usage: prepare_background.py INPUT OUTPUT
"""
import sys

MAX_INPUT_BYTES = 25 * 1024 * 1024  # sanity cap; spec asks to reject "unreasonably large" images
TARGET_SIZE = (1280, 800)


def main():
    if len(sys.argv) != 3:
        print("usage: prepare_background.py INPUT OUTPUT", file=sys.stderr)
        return 2
    src, dst = sys.argv[1], sys.argv[2]

    import os

    try:
        size = os.path.getsize(src)
    except OSError as exc:
        print(f"Cannot stat '{src}': {exc}")
        return 1
    if size == 0:
        print(f"'{src}' is empty.")
        return 1
    if size > MAX_INPUT_BYTES:
        print(f"'{src}' is {size} bytes, larger than the {MAX_INPUT_BYTES} byte cap.")
        return 1

    try:
        from PIL import Image
    except ImportError:
        print(
            "Python Pillow is required to process the background image. "
            "Install it with: sudo apt-get install -y python3-pil"
        )
        return 1

    try:
        img = Image.open(src)
        img.verify()
        img = Image.open(src)  # re-open: verify() invalidates the handle
    except Exception as exc:  # noqa: BLE001 - want to report any decode failure
        print(f"'{src}' is not a readable PNG/JPEG image: {exc}")
        return 1

    if img.format not in ("PNG", "JPEG"):
        print(f"'{src}' is format {img.format}, only PNG and JPEG are supported.")
        return 1

    img = img.convert("RGB")

    # Fit inside TARGET_SIZE preserving aspect ratio, then letterbox onto a
    # black 1280x800 canvas -- avoids distorting the user's image while
    # still matching the exact resolution the build system expects.
    fitted = img.copy()
    fitted.thumbnail(TARGET_SIZE, Image.LANCZOS)
    canvas = Image.new("RGB", TARGET_SIZE, (0, 0, 0))
    offset = ((TARGET_SIZE[0] - fitted.width) // 2, (TARGET_SIZE[1] - fitted.height) // 2)
    canvas.paste(fitted, offset)

    # Match the shipped default's format: 8-bit indexed/palette PNG.
    indexed = canvas.convert("P", palette=Image.ADAPTIVE, colors=256)
    indexed.save(dst, format="PNG")

    print(f"Converted '{src}' -> '{dst}' (1280x800, 8-bit palette PNG)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
