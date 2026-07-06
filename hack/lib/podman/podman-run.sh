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
    debug "Starting ${FUNCNAME[0]}()"
    podman_options=(
        "--user=${__PODMAN_CONTAINER_USER}"
        "--security-opt=label=disable"
        "--mount=type=bind,src=./,target=${__PODMAN_CONTAINER_WORKDIR},ro=true,bind-nonrecursive,bind-propagation=slave,no-dereference"
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

if [ "${__bash_utils_base_config_logging_sourced:-}" != "true" ]; then
    declare __bash_utils_base_config_logging="hack/vendor/bash-utils/lib/base-config-logging.sh"
    [ -f "$__bash_utils_base_config_logging" ] || { printf '%s\n' "failed to find file: $__bash_utils_base_config_logging" >&2; exit 1; }
    # shellcheck source=../../vendor/bash-utils/lib/base-config-logging.sh
    . "$__bash_utils_base_config_logging"
    unset __bash_utils_base_config_logging
fi
