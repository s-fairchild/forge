#!/bin/bash

[ "${XTRACE:-0}" -eq 1 ] && set -x

set -o nounset \
    -o errexit \
    -o pipefail \
    -o noclobber \
    -o hashall

main() {
    info "starting"
    local serve="$1"

    httpd "$serve"
}

if [ "${__lib_logging_sourced:-}" != "true" ]; then
    declare -r __lib_logging="hack/lib/logging.sh"
    [ -f "$__lib_logging" ] || { printf '%s\n' "failed to find file: $__lib_logging" >&2; exit 1; }
    # shellcheck source=../lib/logging.sh
    . "$__lib_logging"
fi

if [ "${__hack_lib_ignition_serve_sourced:-}" != "true" ]; then
    declare -r __hack_lib_ignition_serve="hack/lib/ignition/serve.sh"
    [ -f "$__hack_lib_ignition_serve" ] || fatal "$ERROR_FILE_NOT_FOUND: $__hack_lib_ignition_serve"
    # shellcheck source=../lib/ignition/serve.sh
    . "$__hack_lib_ignition_serve"
fi

main "$@"
