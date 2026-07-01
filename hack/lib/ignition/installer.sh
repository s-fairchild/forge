# hack/lib/ignition/installer.sh
#
# shellcheck shell=bash

[ "${XTRACE:-0}" -eq 1 ] && set -x

declare -r __hack_lib_ignition_installer_sourced="true"
declare -r __INSTALLER_WORKDIR="/data"

coreos-installer() {
    debug "Starting ${FUNCNAME[0]}()"

    local -r image="quay.io/coreos/coreos-installer:release"

    local -r mount_src_dir="${INSTALLER_VOLUME_MOUNT:-$PWD}"
    local -a podman_run_options=(
        "--log-level=${PODMAN_LOG_LEVEL:-warn}"
        "-i"
        "--rm"
        "--env='BU_*'"
        "--security-opt=label=disable"
        "--mount=type=bind,src=${mount_src_dir},target=$__INSTALLER_WORKDIR,bind-propagation=rslave,no-dereference,ro=false"
        "--workdir=$__INSTALLER_WORKDIR"
    )
    debug "$(declare -p mount_src_dir)"
    debug "$(declare -p __INSTALLER_WORKDIR)"

    if [ -v INSTALLER_SECRET_MOUNTS ]; then
        debug "$(declare -p INSTALLER_SECRET_MOUNTS)"
        # shellcheck disable=SC2068
        for i in ${INSTALLER_SECRET_MOUNTS[@]}; do
            podman_run_options+=("$i")
        done
    fi

    debug "$(declare -p image)"
    debug "$(declare -p podman_run_options)"
    debug "coreos-installer options:\n$*"

    # shellcheck disable=SC2068
    podman run \
        ${podman_run_options[@]} \
        "$image" \
        "$@"
}

export -f coreos-installer

if [ "${__lib_vendor_bash_utils_logging_sourced:-}" != "true" ]; then
    declare -r __bash_utils_base_config_logging="hack/vendor/bash-utils/lib/base-config-logging.sh"
    [ -f "$__bash_utils_base_config_logging" ] || { printf '%s\n' "failed to find file: $__bash_utils_base_config_logging" >&2; exit 1; }
    # shellcheck source=../../vendor/bash-utils/lib/base-config-logging.sh
    . "$__bash_utils_base_config_logging"
fi
