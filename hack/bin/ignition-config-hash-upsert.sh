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

err_file_not_found="could not find file to source"
if [ "${__lib_opt_bash_utils_logging_sourced:-}" != "true" ]; then
    declare -r shell_utils_logging="hack/lib/opt-bash-utils-logging.sh"

    [ -f "$shell_utils_logging" ] || "$(echo "${err_file_not_found}: $shell_utils_logging"; exit 5)"
    # shellcheck source=../lib/opt-bash-utils-logging.sh
    . "$shell_utils_logging"
fi

if [ "${__hack_lib_hash_sourced:-}" != "true" ]; then
    declare -r hash_lib="hack/lib/hash.sh"

    [ -f "$hash_lib" ] || fatal "${err_file_not_found}: $hash_lib"
    # shellcheck source=../lib/hash.sh
    . "$hash_lib"
fi

if [ "${__hack_lib_yq_sourced:-}" != "true" ]; then
    declare -r yq_lib="hack/lib/yq.sh"

    [ -f "$yq_lib" ] || fatal "${err_file_not_found}: $yq_lib"
    # shellcheck source=../lib/yq.sh
    . "$yq_lib"
fi

main "$@"
