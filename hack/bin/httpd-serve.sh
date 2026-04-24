#!/bin/bash

set -o nounset \
    -o errexit

DEBUG="${DEBUG:-"false"}"
if [ "$DEBUG" == "true" ]; then
    set -x
fi

main() {
    info "starting"
    local serve="$1"

    podman volume exists "$serve" || warn "$serve will be mounted to the container directly."

    httpd "$serve"
}

if [ "${__bash_utils_util_base_sourced:-}" != "true" ]; then
    # declare -r __bash_utils_util_base_path="hack/opt/bash-utils/util/base.sh"
    declare -r __bash_utils_util_base_path="hack/opt/bash-utils/util/base.sh"

    [ -f "$__bash_utils_util_base_path" ] || "$(echo "$__bash_utils_util_base_path file not found."; exit 5)"
    # shellcheck source=../opt/bash-utils/util/base.sh
    . "$__bash_utils_util_base_path"
fi

if [ "${__bash_utils_util_logging_sourced:-}" != "true" ]; then
    # declare -r __bash_utils_util_logging_path="hack/opt/bash-utils/util/logging.sh"
    declare -r __bash_utils_util_logging_path="hack/opt/bash-utils/util/logging.sh"

    [ -f "$__bash_utils_util_logging_path" ] || "$(echo "$__bash_utils_util_base_path file not found."; exit 5)"
    # shellcheck source=../opt/bash-utils/util/logging.sh
    . "$__bash_utils_util_logging_path"
fi

if [ "${__hack_lib_httpd_sourced:-}" != "true" ]; then
    # declare -r __hack_lib_httpd_path="hack/lib/httpd.sh"
    declare -r __hack_lib_httpd_path="hack/lib/httpd.sh"

    [ -f "$__hack_lib_httpd_path" ] || fatal "File not found $__hack_lib_httpd_path. Cannot source."
    # shellcheck source=../lib/httpd.sh
    . "$__hack_lib_httpd_path"
fi

main "$@"
