#!/bin/bash

set -o errexit \
    -o nounset

main () {
    local -r hash_file="${1?'hash file must be provided.'}"
    local -r upsert_file="${2?'a yaml file must be provided for inserting the parsed hash value.'}"

    local verification_hash
    format_hash "$hash_file" verification_hash

    upsert_hash_value "$upsert_file" "$verification_hash"
}

# TODO Add logging
# TODO move these functions into a separate library file to be sourced.
# TODO import shell-utils utils after library file move

# format_hash()
format_hash() {
    local file="$1"
    local -n out="$2"

    local checksum
    parse_hash_extension "$file" checksum
    local type
    parse_hash_value "$file" type

    # Reference: https://coreos.github.io/butane/config-fcos-v1_5
    # shellcheck disable=SC2034
    out="$type-$checksum"
}

# upsert_hash_value()
upsert_hash_value() {
    local -r f="$1"
    local -rx YQ_VALUE="$2"

    yq -P \
        -oj \
        -i \
        '.ignition.config.merge.[0].verification.hash |= strenv(YQ_VALUE)' \
        "$f"
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
