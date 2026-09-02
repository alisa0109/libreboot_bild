#!/usr/bin/env bash
# Final ROM verification and output staging (spec sections 17-18).
#
# The 12 MiB full-build ROM must be split back into the two physical
# chip-sized images before it can actually be flashed (see lib/layout.sh
# for the confirmed offsets) -- libreboot's own build docs perform exactly
# this split with `dd bs=1M count=8` / `dd bs=1M skip=8`.

OUTPUT_DIR="$ROOT_DIR/output"
VERIFY_DUMP_PY="$ROOT_DIR/tools/verify_dump.py"

readonly FULL_ROM_SIZE=12582912   # 12 MiB
readonly SPI1_SIZE=8388608        # 8 MiB, low offset
readonly SPI2_SIZE=4194304        # 4 MiB, high offset

verify_and_stage_rom() {
    local rom="$1"

    local size
    size=$(stat -c%s "$rom")
    if [[ "$size" -ne "$FULL_ROM_SIZE" ]]; then
        die "BUILD FAILED." \
            "ERROR: Final ROM verification failed." \
            "Built ROM is $size bytes, expected $FULL_ROM_SIZE (12 MiB)." \
            "STOP."
    fi
    log_ok "ROM size (12 MiB)"

    local out
    if ! out=$(python3 "$VERIFY_DUMP_PY" --label "output ROM" "$rom" 2>&1); then
        die "BUILD FAILED." "ERROR: Final ROM verification failed." "$out" "STOP."
    fi
    _log_line "$out"
    log_ok "ROM content sanity (not blank/degenerate)"

    local cbfstool="$LIBREBOOT_DIR/elf/coreboot/default/cbfstool"
    if [[ -x "$cbfstool" ]]; then
        local listing
        listing=$("$cbfstool" "$rom" print 2>>"$LOG_FILE") || \
            die "BUILD FAILED." "ERROR: Final ROM verification failed." \
                "cbfstool could not read the built ROM's CBFS." "STOP."
        if ! grep -qi 'grub' <<<"$listing"; then
            die "BUILD FAILED." "ERROR: Final ROM verification failed." \
                "No GRUB payload entry found in CBFS." "STOP."
        fi
        _log_line "$listing"
        log_ok "GRUB2 payload present in ROM (CBFS)"
    else
        log_warn "cbfstool not found -- skipping CBFS payload listing check."
    fi

    local ifdtool="$LIBREBOOT_DIR/elf/coreboot/default/ifdtool"
    if [[ -x "$ifdtool" ]]; then
        if ! "$ifdtool" -d "$rom" >>"$LOG_FILE" 2>&1; then
            die "BUILD FAILED." "ERROR: Final ROM verification failed." \
                "ifdtool could not parse the Intel Flash Descriptor in the built ROM." \
                "STOP."
        fi
        log_ok "Intel Flash Descriptor valid in ROM"
    else
        log_warn "ifdtool not found -- skipping descriptor check."
    fi

    mkdir -p "$OUTPUT_DIR"
    local full_out="$OUTPUT_DIR/t440p-libreboot.rom"
    cp "$rom" "$full_out"
    sha256_of "$full_out" | awk -v f="$(basename "$full_out")" '{print $1"  "f}' > "$full_out.sha256"

    local spi1_out="$OUTPUT_DIR/t440p-libreboot-spi1-8mb.rom"
    local spi2_out="$OUTPUT_DIR/t440p-libreboot-spi2-4mb.rom"
    dd if="$full_out" of="$spi1_out" bs=1M count=8 status=none || \
        die "ERROR: Final ROM verification failed." "Could not split SPI1 (8 MiB) image." "STOP."
    dd if="$full_out" of="$spi2_out" bs=1M skip=8 status=none || \
        die "ERROR: Final ROM verification failed." "Could not split SPI2 (4 MiB) image." "STOP."

    local s1 s2
    s1=$(stat -c%s "$spi1_out"); s2=$(stat -c%s "$spi2_out")
    [[ "$s1" -eq "$SPI1_SIZE" ]] || die "ERROR: SPI1 split has wrong size ($s1, expected $SPI1_SIZE). STOP."
    [[ "$s2" -eq "$SPI2_SIZE" ]] || die "ERROR: SPI2 split has wrong size ($s2, expected $SPI2_SIZE). STOP."

    sha256_of "$spi1_out" | awk -v f="$(basename "$spi1_out")" '{print $1"  "f}' > "$spi1_out.sha256"
    sha256_of "$spi2_out" | awk -v f="$(basename "$spi2_out")" '{print $1"  "f}' > "$spi2_out.sha256"

    log_ok "Final verification"
    FINAL_ROM_FULL="$full_out"
    FINAL_ROM_SPI1="$spi1_out"
    FINAL_ROM_SPI2="$spi2_out"
    FINAL_ROM_SHA256=$(sha256_of "$full_out")
}
