# hack/lib/podman/podman-volume.sh
#
# shellcheck shell=bash

declare -r __lib_podman_volume_sourced="true"

podman_volume_exists() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 1 "$@" || return 1
    local -r v="$1"

    if ! podman volume exists "$v"; then
        error "podman volume $v not found."
        return 1
    fi
}

podman_volume_create() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 1 "$@" || return 1
    local -r v="$1"

    # Possible nice to have features here
    #   * populate label overlay
    #   * populate bootstrap with butane or ignition
    #   * accept array of labels to apply, expand them with --label prefixing each string
    if podman volume exists "$v"; then
        warn "podman volume already exists. Refusing to replace. Manually delete this volume and re-run."
    else
        podman volume \
                create \
                --ignore \
                --label project="$(basename "$PWD")" \
                "$v" \
        || fatal "Failed to create podman volume: $v"
    fi
}

# podman_volume_export_untar_stdout()
podman_volume_export_untar_stdout() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 2 "$@" || return 1
    vol="$1"
    target="$2"

    info "Extracting ${target} to stdout from podman volume ${vol}."
    podman volume \
           export \
           "$vol" \
           | tar x "$target" -O
}

if [ "${__bash_logger_adapter_sourced:-}" != "true" ]; then
    declare __bash_logger_adapter_path="hack/vendor/bash-logger-adapter/adapter.sh"
    [ -f "$__bash_logger_adapter_path" ] || { printf '%s\n' "failed to find file: $__bash_logger_adapter_sourced" >&2; exit 1; }
    # shellcheck source=../../vendor/bash-logger-adapter/adapter.sh
    . "$__bash_logger_adapter_path"
    unset __bash_logger_adapter_path
fi

if [ "${__vendor_bashkit_local_lib_bashkit_options_operands_utils_sourced:-}" != "true" ]; then
    declare __vendor_bashkit_local_lib_bashkit_options_operands_utils="hack/vendor/bashkit/local/lib/bashkit/options-operands-utils.sh"
    [ -f "$__vendor_bashkit_local_lib_bashkit_options_operands_utils" ] || fatal "${ERROR_FILE_NOT_FOUND}: ${__vendor_bashkit_local_lib_bashkit_options_operands_utils}"
    # shellcheck source=../../vendor/bashkit/local/lib/bashkit/options-operands-utils.sh
    . "$__vendor_bashkit_local_lib_bashkit_options_operands_utils"
    unset __vendor_bashkit_local_lib_bashkit_options_operands_utils
fi
