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

declare -r yq_lib="hack/lib/yq.sh"
[ -f "$yq_lib" ] || "$(echo "cannot source $yq_lib. file not found."; exit 1)"
# shellcheck source=../lib/yq.sh
. "$yq_lib"

main "$@"
