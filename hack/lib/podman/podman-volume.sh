# hack/lib/podman/podman-volume.sh
#
# shellcheck shell=bash

declare -r __lib_podman_volume_sourced="true"

podman_volume_exists() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    local -r v="${1?$(fatal "$ERROR_ARG_REQUIRED: \$1 - podman volume must be provided.")}"

    if ! podman volume exists "$v"; then
        error "podman volume $v does not exist."
        return 1
    fi
}

podman_volume_create() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
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

# podman_volume_export_untar_stdout()
podman_volume_export_untar_stdout() {
    vol="${1?$(fatal "$ERROR_ARG_REQUIRED")}"
    target="${2?$(fatal "$ERROR_ARG_REQUIRED")}"

    podman volume \
           export \
           "$vol" \
           | tar x "$target" -O
}

if [ "${__hack_env_vendor_sourced:-}" != "true" ]; then
    declare __hack_env_vendor="hack/env/vendor.env"
    [ -f "$__hack_env_vendor" ] || { printf '%s\n' "failed to find file: $__hack_env_vendor" >&2; exit 1; }
    # shellcheck source=../../env/vendor.env
    . "$__hack_env_vendor"
    unset __hack_env_vendor
fi
