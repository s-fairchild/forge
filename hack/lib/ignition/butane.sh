# hack/lib/ignition/butane.sh
#
# shellcheck shell=bash

# declare -r __hack_lib_ignition_butane_sourced="true"
#
declare -r __hack_lib_ignition_butane_sourced="true"

# butane()
#
# Runs ignition in a container with image quay.io/coreos/butane:release
#
# Environment:
#   * PODMAN_LOG_LEVEL - string; Set to change the default podman run log level.
#   * BUTANE_VOLUME_MOUNT - string; full directory path or volume name to be mounted as the working directory.
#   * BUTANE_SECRET_MOUNTS - nameref; array of podman secret mount options. Appended to podman_run_options.
#
# args:
#   * $@) all arguments are passed to the container
butane() {
    podman_run_options=(
        "--log-level=${PODMAN_LOG_LEVEL:-warn}"
        "-i"
        "--rm"
        "--env='BU_*'"
        "--volume=${BUTANE_VOLUME_MOUNT:-$PWD}:$__BUTANE_WORKDIR:O"
        "--workdir=$__BUTANE_WORKDIR"
    )

    if [ -v BUTANE_SECRET_MOUNTS ]; then
        # array must be expanded as a string here or it will append an extra space ' '
        # mapfile -O $(( "${#BUTANE_SECRET_MOUNTS[@]}" + 1 )) \
                # -d ' ' \
                # podman_run_options \
                # <<< "${BUTANE_SECRET_MOUNTS[*]}"
        # shellcheck disable=SC2068
        for i in ${BUTANE_SECRET_MOUNTS[@]}; do
            podman_run_options+=("$i")
        done

    fi

    local -r image="quay.io/coreos/butane:release"
    debug "$(declare -p image)"
    debug "$(declare -p podman_run_options)"
    debug "butane options:\n$*"

    # shellcheck disable=SC2068
    podman run \
        ${podman_run_options[@]} \
        "$image" \
        "$@"
}

export -f butane

if [ "${__lib_opt_bash_utils_logging_sourced:-}" != "true" ]; then
    declare -r __lib_opt_bash_utils_logging="hack/lib/opt-bash-utils-logging.sh"
    [ -f "$__lib_opt_bash_utils_logging" ] || "$(echo "$ERROR_FILE_NOT_FOUND: $__lib_opt_bash_utils_logging"; exit 1)"

    # shellcheck source=../opt-bash-utils-logging.sh
    . "$__lib_opt_bash_utils_logging" || "$(echo "failed to source file: $__lib_opt_bash_utils_logging"; exit 1)"
fi

if [ "${__hack_lib_ignition_constants_sourced:-}" != "true" ]; then
    declare -r __hack_lib_ignition_constants="hack/lib/ignition/constants.env"
    [ -f "$__hack_lib_ignition_constants" ] || fatal "$ERROR_FILE_NOT_FOUND: $__hack_lib_ignition_constants"

    # shellcheck source=constants.env
    . "$__hack_lib_ignition_constants" || fatal "$ERROR_FILE_SOURCE_FAILED: $__hack_lib_ignition_constants"
fi
