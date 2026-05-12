# shellcheck shell=bash

declare -r __hack_lib_hash_sourced="true"

# sha512sum_gen()
sha512sum_gen() {
    # shellcheck disable=SC2016,SC2128
    info "$FUNCNAME: Generating hash file for ${1?'$1 must be provided.'}"

    sha512sum "${1}" > "${1}.sha512" \
    || error "failed to generate checksum for file: $1"
}

# sha512sum_check()
sha512sum_check() {
    # shellcheck disable=SC2016,SC2128
    info "$FUNCNAME: Checking hash for file: ${1?'$1 must be provided.'}"

    sha512sum --check \
        --strict \
        "${1}.sha512" \
    || error "sha512sum check failed for: $1"
}

# format_hash()
format_hash() {
    local -r f="$1"

    [ -f "$f" ] || abort "$f not found."

    local checksum
    parse_hash_extension "$f" checksum
    local type
    parse_hash_value "$f" type

    # Reference: https://coreos.github.io/butane/config-fcos-v1_5
    # shellcheck disable=SC2034
    out="$type-$checksum"
    debug "created verification.hash from file: $f: $out"

    printf "%s" "$out"
}

# parse_hash_extension()
parse_hash_extension() {
    local -n t="$2"

    # shellcheck disable=SC2034
    t="$(cut -d ' ' -f 1 < "$1")"
}

# parse_hash_value()
parse_hash_value() {
    local -n v="$2"

    # shellcheck disable=SC2034
    v="$(basename "$1")"
    v="${v##*.}"
}

if [ "${__lib_opt_bash_utils_logging_sourced:-}" != "true" ]; then
    declare -r shell_utils_logging="hack/lib/opt-bash-utils-logging.sh"

    [ -f "$shell_utils_logging" ] || "$(echo "$shell_utils_logging file not found."; exit 5)"
    # shellcheck source=opt-bash-utils-logging.sh
    . "$shell_utils_logging"
fi
