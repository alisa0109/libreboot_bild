#!/usr/bin/env bash
# T440p flash layout and dump merging (spec section 7).
#
# Confirmed address map (doc.coreboot.org/mainboard/lenovo/t440p.html and
# libreboot.org/docs/install/t440p_external.html -- see README):
#
#   0x000000 - 0x7FFFFF   LOWER chip (SPI1, 8 MiB, base cover)
#                           contains: Flash Descriptor, GbE region,
#                           ME region, start of BIOS region
#   0x800000 - 0xBFFFFF   UPPER chip (SPI2, 4 MiB, small door)
#                           contains: rest of the BIOS region
#
# libreboot's own build docs split a combined 12 MiB image the same way
# (`dd bs=1M count=8` for SPI1, `dd bs=1M skip=8` for SPI2), which is the
# authoritative confirmation of this order: LOWER must come first.

WORK_ORIGINAL_DIR="$ROOT_DIR/work/original"
WORK_BUILD_DIR="$ROOT_DIR/work/build"
VENDOR_ROM="$WORK_BUILD_DIR/vendor.rom"

readonly COMBINED_SIZE=12582912  # 12 MiB = 8 MiB + 4 MiB

verify_t440p_layout() {
    local lower="$WORK_ORIGINAL_DIR/lower_1.bin"
    local upper="$WORK_ORIGINAL_DIR/upper_1.bin"

    [[ -f "$lower" && -f "$upper" ]] || \
        die "ERROR: Invalid T440p ROM layout." \
            "Verified dumps not found in work/original/ -- run dump verification first." \
            "STOP."

    local lower_size upper_size
    lower_size=$(stat -c%s "$lower")
    upper_size=$(stat -c%s "$upper")

    if [[ "$lower_size" -ne 8388608 || "$upper_size" -ne 4194304 ]]; then
        die "ERROR: Invalid T440p ROM layout." \
            "LOWER must be exactly 8388608 bytes (got $lower_size)." \
            "UPPER must be exactly 4194304 bytes (got $upper_size)." \
            "STOP."
    fi

    log_ok "T440p layout (LOWER 8 MiB @ 0x000000, UPPER 4 MiB @ 0x800000)"
}

merge_dumps() {
    mkdir -p "$WORK_BUILD_DIR"
    local lower="$WORK_ORIGINAL_DIR/lower_1.bin"
    local upper="$WORK_ORIGINAL_DIR/upper_1.bin"

    # LOWER first, then UPPER -- mirrors the confirmed address order.
    cat "$lower" "$upper" > "$VENDOR_ROM" || \
        die "ERROR: Failed to merge dumps into $VENDOR_ROM. STOP."

    local size
    size=$(stat -c%s "$VENDOR_ROM")
    if [[ "$size" -ne "$COMBINED_SIZE" ]]; then
        rm -f "$VENDOR_ROM"
        die "ERROR: Invalid T440p ROM layout." \
            "Merged image is $size bytes, expected $COMBINED_SIZE (12 MiB)." \
            "STOP."
    fi

    log_ok "Merged vendor.rom (12 MiB, LOWER+UPPER)"
}
