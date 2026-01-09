# shellcheck shell=bash

# declare -r shell_utils_lib="shell-utils/usr/local/lib/utils.sh"
declare -r shell_utils_lib="shell-utils/usr/local/lib/utils.sh"

[ -f "$shell_utils_lib" ] || "$(echo "$shell_utils_lib file not found."; exit 1)"
# shellcheck source=../../shell-utils/usr/local/lib/utils.sh
source "$shell_utils_lib"

if_debug_set_xtrace

# upsert_hash_value()
upsert_hash_value() {
    local -r f="$1"
    local -rx YQ_VALUE="$2"
    log "starting"

    [ -f "$f" ] || abort "$f not found."

    local -x YQ_KEY=".ignition.config.merge.[0].verification.hash"
    log "Editing $f inplace."
    log "upserting hash into - $f:$YQ_KEY"

    yq -P \
        -oj \
        -i \
        'strenv(YQ_KEY) |= strenv(YQ_VALUE)' \
        "$f"
}

# format_hash()
format_hash() {
    local f="$1"
    local -n out="$2"
    log "starting"

    [ -f "$f" ] || abort "$f not found."

    local checksum
    parse_hash_extension "$f" checksum
    local type
    parse_hash_value "$f" type

    # Reference: https://coreos.github.io/butane/config-fcos-v1_5
    # shellcheck disable=SC2034
    out="$type-$checksum"
    log "created butane verification.hash: $out"
}

# parse_hash_extension()
parse_hash_extension() {
    local -n t="$2"
    log "starting"

    # shellcheck disable=SC2034
    t="$(cut -d ' ' -f 1 < "$1")"
}

# parse_hash_value()
parse_hash_value() {
    local -n v="$2"
    log "starting"

    # shellcheck disable=SC2034
    v="$(basename "$1")"
    v="${v##*.}"
}

# eval_compression()
eval_compression() {
    # shellcheck disable=SC2034
    local -n value="$2"
    log "starting"

    local -x YQ_KEY=".ignition.config.*.[].compression"
    eval "$(yq -o shell 'strenv(YQ_KEY) | select(. != "null")' "$1")"
    log "$1: $YQ_KEY=$value"
}
