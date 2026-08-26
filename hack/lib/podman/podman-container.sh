# shellcheck shell=bash

declare -r __lib_podman_run_sourced="true"

declare -r __PODMAN_CONTAINER_USER="podman"
declare -r __PODMAN_CONTAINER_WORKDIR="/home/podman/data"
declare -r __PODMAN_CONTAINER_GRAPHROOT_USER_PODMAN_VOLUME_NAME="graphroot-user-podman"
declare -r __PODMAN_CONTAINER_GRAPHROOT_USER_PODMAN_TARGET="/home/podman/.local/share/containers/storage"

declare -r __PODMAN_CONTAINER_VOLUME_GRAPHROOT_USER_PODMAN="graphroot-user-podman"
declare -r __PODMAN_CONTAINER_VOLUME_TARGET_GRAPHROOT_USER_PODMAN="/home/podman/.local/share/containers/storage"

# podman_container_run()
podman_container() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    podman_options=(
        "--user=${__PODMAN_CONTAINER_USER}"
        "--security-opt=label=disable"
        "--workdir=${__PODMAN_CONTAINER_WORKDIR}"
        "--volume=${__PODMAN_CONTAINER_VOLUME_GRAPHROOT_USER_PODMAN}:${__PODMAN_CONTAINER_VOLUME_TARGET_GRAPHROOT_USER_PODMAN}"
        "--rm"
        "-i"
    )
    local -r image="registry.redhat.io/ubi10/podman:latest"

    # shellcheck disable=SC2068
    podman run \
           ${podman_options[@]} \
           "$image" \
           podman \
           ${@}
}

if [ "${__bash_logger_adapter_sourced:-}" != "true" ]; then
    declare __bash_logger_adapter_path="hack/vendor/bash-logger-adapter/adapter.sh"
    [ -f "$__bash_logger_adapter_path" ] || { printf '%s\n' "failed to find file: $__bash_logger_adapter_sourced" >&2; exit 1; }
    # shellcheck source=../../vendor/bash-logger-adapter/adapter.sh
    . "$__bash_logger_adapter_path"
    unset __bash_logger_adapter_path
fi
