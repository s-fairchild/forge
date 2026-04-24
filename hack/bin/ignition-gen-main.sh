#!/bin/bash
# Recursively generate all ignition files

set -o nounset \
    -o errexit

DEBUG="${DEBUG:-"false"}"
if [ "$DEBUG" == "true" ]; then
    set -x
fi

main() {
    local -r butane_main="${1?'main butane file must be specified.'}"

    # shellcheck disable=SC2128
    info "$FUNCNAME: starting"

    # shellcheck disable=SC2034
    butane_main_json="$(gen_ign_config_merge_inlines "$butane_main")"
    podman_secret_create_ignition "$butane_main" butane_main_json
}

if [ "${__ignition_common_lib_sourced:-}" != "true" ]; then
    # declare -r __ignition_common_lib="hack/lib/ignition/lib/common.env"
    declare -r __ignition_common_lib="hack/lib/ignition/common.env"
    [ -f "$__ignition_common_lib" ] || "$(echo "$__ignition_common_lib FATAL file not found."; exit 5)"

    VERBOSE="${VERBOSE:-0}"
    # shellcheck source=../lib/ignition/common.env
    . "$__ignition_common_lib"
fi

main "$@"
