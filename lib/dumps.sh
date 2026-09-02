#!/usr/bin/env bash
# BIOS dump discovery and verification (spec sections 4-6, 19-20).
#
# T440p has two physical SPI flash chips: an 8 MiB chip at the low address
# range (under the base cover) and a 4 MiB chip at the high address range
# (under the small door). Each should be read twice with flashprog/flashrom
# for reliability -- this is libreboot's own documented recommendation
# (see README), not an invention of this tool.
#
# This module NEVER writes to dumps/. It only reads from there and, once a
# dump is fully verified, copies it into work/original/.

readonly UPPER_SIZE=4194304   # 4 MiB -- SPI2, door-accessible chip, high offset
readonly LOWER_SIZE=8388608   # 8 MiB -- SPI1, base-cover chip, low offset (contains IFD)

DUMPS_DIR="$ROOT_DIR/dumps"
WORK_ORIGINAL_DIR="$ROOT_DIR/work/original"
VERIFY_DUMP_PY="$ROOT_DIR/tools/verify_dump.py"

declare -A DUMP_SHA256=()

_require_dump_file() {
    local path="$1"
    if [[ ! -f "$path" ]]; then
        die "ERROR: BIOS dump not found." \
            "Expected file: $path" \
            "Place your four dump files in dumps/ before running this tool." \
            "STOP."
    fi
    if [[ -L "$path" ]]; then
        die "ERROR: $path is a symlink, refusing to use it as a BIOS dump. STOP."
    fi
}

_check_size() {
    local path="$1" expected="$2" label="$3"
    local actual
    actual=$(stat -c%s "$path")
    if [[ "$actual" -ne "$expected" ]]; then
        die "ERROR:" \
            "Invalid BIOS dump size." \
            "" \
            "Expected:" \
            "$label: $expected bytes" \
            "" \
            "Actual:" \
            "$label ($path): $actual bytes" \
            "" \
            "STOP."
    fi
    log_ok "$label size ($(human_bytes "$expected"))"
}

_check_pair_matches() {
    local path1="$2" path2="$3" label="$1"
    local h1 h2
    h1=$(sha256_of "$path1")
    h2=$(sha256_of "$path2")
    DUMP_SHA256["$path1"]="$h1"
    DUMP_SHA256["$path2"]="$h2"
    if [[ "$h1" != "$h2" ]]; then
        die "ERROR:" \
            "BIOS dump verification failed." \
            "" \
            "The two copies of the $label dump are different." \
            "" \
            "  $(basename "$path1"): $h1" \
            "  $(basename "$path2"): $h2" \
            "" \
            "Do NOT continue." \
            "This usually means a bad SPI programmer connection -- re-read" \
            "both copies of the $label chip and try again."
    fi
    log_ok "$label SHA256 match ($h1)"
}

_structural_check() {
    local path="$1" label="$2" expect_ifd="$3"
    local args=(--label "$label")
    [[ "$expect_ifd" == "true" ]] && args+=(--expect-ifd)
    local out
    if ! out=$(python3 "$VERIFY_DUMP_PY" "${args[@]}" "$path" 2>&1); then
        die "ERROR: BIOS dump structural verification failed." "$out" "STOP."
    fi
    _log_line "$out"
    log_ok "$label structural check"
}

verify_dumps() {
    log_info "Verifying BIOS dumps in dumps/ ..."

    local upper1="$DUMPS_DIR/upper_1.bin" upper2="$DUMPS_DIR/upper_2.bin"
    local lower1="$DUMPS_DIR/lower_1.bin" lower2="$DUMPS_DIR/lower_2.bin"

    for f in "$upper1" "$upper2" "$lower1" "$lower2"; do
        _require_dump_file "$f"
    done
    log_ok "All 4 dump files present"

    _check_size "$upper1" "$UPPER_SIZE" "UPPER dump #1"
    _check_size "$upper2" "$UPPER_SIZE" "UPPER dump #2"
    _check_size "$lower1" "$LOWER_SIZE" "LOWER dump #1"
    _check_size "$lower2" "$LOWER_SIZE" "LOWER dump #2"

    _check_pair_matches "UPPER" "$upper1" "$upper2"
    _check_pair_matches "LOWER" "$lower1" "$lower2"

    _structural_check "$upper1" "UPPER dump" "false"
    _structural_check "$lower1" "LOWER dump" "true"

    mkdir -p "$WORK_ORIGINAL_DIR"
    install -m 0444 "$upper1" "$WORK_ORIGINAL_DIR/upper_1.bin"
    install -m 0444 "$lower1" "$WORK_ORIGINAL_DIR/lower_1.bin"
    log_ok "Verified dumps copied to work/original/ (read-only)"
}
