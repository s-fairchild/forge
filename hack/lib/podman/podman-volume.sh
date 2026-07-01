# hack/lib/podman/podman-volume.sh
#
# shellcheck shell=bash

declare -r __lib_podman_volume_sourced="true"

podman_volume_exists() {
    debug "Starting ${FUNCNAME[0]}()"
    local -r v="${1?$(fatal "$ERROR_ARG_REQUIRED: \$1 - podman volume must be provided.")}"

    if ! podman volume exists "$v"; then
        error "podman volume $v does not exist."
        return 1
    fi
}

podman_volume_create() {
    debug "Starting ${FUNCNAME[0]}()"
    local -r v="$1"

    if podman volume exists "$v"; then
        warn "podman volume already exists $v\nDeleting podman volume: $v"
        podman volume rm "$v"
    fi

    # Possible nice to have features here
    #   * populate label overlay
    #   * populate bootstrap with butane or ignition
    #   * accept array of labels to apply, expand them with --label prefixing each string
    podman volume \
            create \
            --ignore \
            --label project="$(basename "$PWD")" \
            "$v" \
    || fatal "Failed to create podman volume: $v"
}

if [ "${__bash_utils_base_config_logging_sourced:-}" != "true" ]; then
    declare -r __bash_utils_base_config_logging="hack/vendor/bash-utils/lib/base-config-logging.sh"
    [ -f "$__bash_utils_base_config_logging" ] || { printf '%s\n' "failed to find file: $__bash_utils_base_config_logging" >&2; exit 1; }
    # shellcheck source=../../vendor/bash-utils/lib/base-config-logging.sh
    . "$__bash_utils_base_config_logging"
fi
