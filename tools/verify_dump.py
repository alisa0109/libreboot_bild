#!/usr/bin/env python3
"""Structural sanity checks for a raw SPI flash dump.

Called by lib/dumps.sh after the size and duplicate-copy SHA256 checks have
already passed. SHA256 only proves two reads are identical to each other --
it says nothing about whether either read is actually a sane BIOS image
(e.g. both copies could be a consistent all-0xFF read from a chip that
never got selected). This script checks that the bytes actually look like
firmware.

Exit code 0 = looks structurally sane. Non-zero = fails, with a one-line
reason on stdout the caller surfaces to the user.
"""
import argparse
import struct
import sys
from collections import Counter

# Intel Flash Descriptor signature ("FLVALSIG"), a 32-bit little-endian
# word at byte offset 0x10 of the descriptor region. The descriptor always
# sits at the very start of the low/base flash chip on this platform.
IFD_SIGNATURE_OFFSET = 0x10
IFD_SIGNATURE = 0x0FF0A55A

# A dump that is >99% a single repeated byte (0xFF erased, or 0x00 unread)
# is not a real firmware image -- it's a bad/failed read.
BLANK_FRACTION_THRESHOLD = 0.99


def read_file(path):
    with open(path, "rb") as f:
        return f.read()


def check_not_blank(data, label):
    counts = Counter(data)
    total = len(data)
    for byte_value in (0xFF, 0x00):
        frac = counts.get(byte_value, 0) / total
        if frac >= BLANK_FRACTION_THRESHOLD:
            print(
                f"{label}: {frac*100:.1f}% of bytes are 0x{byte_value:02X} -- "
                f"this looks like a blank/failed read, not a real BIOS dump."
            )
            return False
    return True


def check_entropy_sanity(data, label):
    # A real BIOS image is a mix of compressed blobs, code and padding, so
    # its byte-value histogram is broad. A degenerate read (e.g. one where
    # the programmer only ever toggled a couple of data lines) collapses to
    # a handful of distinct byte values across the whole file.
    counts = Counter(data)
    distinct = len(counts)
    if distinct < 32:
        print(
            f"{label}: only {distinct} distinct byte values across "
            f"{len(data)} bytes -- does not look like real firmware content."
        )
        return False
    return True


def check_ifd_signature(data, label):
    if len(data) < IFD_SIGNATURE_OFFSET + 4:
        print(f"{label}: too short to contain an Intel Flash Descriptor.")
        return False
    (sig,) = struct.unpack_from("<I", data, IFD_SIGNATURE_OFFSET)
    if sig != IFD_SIGNATURE:
        print(
            f"{label}: Intel Flash Descriptor signature not found at "
            f"offset 0x{IFD_SIGNATURE_OFFSET:X} "
            f"(expected 0x{IFD_SIGNATURE:08X}, found 0x{sig:08X})."
        )
        return False
    return True


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("path", help="path to the dump file")
    ap.add_argument("--label", default=None, help="human label for messages")
    ap.add_argument(
        "--expect-ifd",
        action="store_true",
        help="also require a valid Intel Flash Descriptor signature "
        "(use this only for the LOWER/base-chip dump, which contains "
        "the descriptor)",
    )
    args = ap.parse_args()

    label = args.label or args.path
    try:
        data = read_file(args.path)
    except OSError as exc:
        print(f"{label}: cannot read file: {exc}")
        return 1

    if len(data) == 0:
        print(f"{label}: file is empty.")
        return 1

    ok = True
    ok &= check_not_blank(data, label)
    ok &= check_entropy_sanity(data, label)
    if args.expect_ifd:
        ok &= check_ifd_signature(data, label)

    if ok:
        print(f"{label}: structural checks passed.")
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
