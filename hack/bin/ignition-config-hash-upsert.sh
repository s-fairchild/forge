#!/bin/bash

set -o errexit \
    -o nounset

main () {
    local -r hash_file="${1?'hash file must be provided.'}"

    local verification_hash
    format_hash "$hash_file" verification_hash

    echo "$verification_hash"
}

# TODO move these functions into a separate library file to be sourced.

# format_hash()
format_hash() {
    local f="$1"
    local -n hash_str="$2"

    local checksum
    parse_hash_extension "$f" checksum
    local type
    parse_hash_value "$f" type

    # shellcheck disable=SC2034
    hash_str="$type-$checksum"
}

# eval_compression()
eval_compression() {
    # shellcheck disable=SC2034
    local -n value="$2"

    eval "$(yq -o shell '.ignition.config.*.[].compression | select(. != "null")' "$1")"
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

main "$@"
