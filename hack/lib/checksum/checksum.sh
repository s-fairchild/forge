# shellcheck shell=bash

if [ "${__hack_lib_checksum_format_sourced:-}" != "true" ]; then
    declare -r __hack_lib_checksum_format="hack/lib/checksum/format.sh"
    [ -f "$__hack_lib_checksum_format" ] || return 1
    # shellcheck source=format.sh
    . "$__hack_lib_checksum_format"
fi

if [ "${__hack_lib_checksum_sha512sum_sourced:-}" != "true" ]; then
    declare -r __hack_lib_checksum_sha512sum="hack/lib/checksum/sha512sum.sh"
    [ -f "$__hack_lib_checksum_sha512sum" ] || return 1
    # shellcheck source=sha512sum.sh
    . "$__hack_lib_checksum_sha512sum"
fi
