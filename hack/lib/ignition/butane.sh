# hack/lib/ignition/butane.sh
#
# shellcheck shell=bash

declare -r __hack_lib_ignition_butane_sourced="true"
declare -r __BUTANE_WORKDIR="/data"
declare -r __BUTANE_FILES_DIR="files"

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
    debug "Starting ${FUNCNAME[0]}()"

    local -r mount_src_dir="${BUTANE_VOLUME_MOUNT:-$PWD}"
    podman_run_options=(
        "--log-level=${PODMAN_LOG_LEVEL:-warn}"
        "-i"
        "--rm"
        "--env='BU_*'"
        "--security-opt=label=disable"
        "--mount=type=bind,src=${mount_src_dir},target=$__BUTANE_WORKDIR,bind-propagation=rslave,no-dereference,ro=true"
        "--workdir=$__BUTANE_WORKDIR"
    )
    debug "$(declare -p mount_src_dir)"
    debug "$(declare -p __BUTANE_WORKDIR)"

    if [ -v BUTANE_SECRET_MOUNTS ]; then
        debug "$(declare -p BUTANE_SECRET_MOUNTS)"
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

# butane_check()
#
# Validates an ignition JSON document by passing it to butane --check --strict
# (butane -cs) via stdin.  Aborts with fatal() on validation failure or empty input.
#
# args:
#   * stdin) ignition JSON string to validate.
butane_check() {
    debug "Starting ${FUNCNAME[0]}()"
    local -r files_dir="${1:-}"
    local -r input="$(cat)"
    [ -z "$input" ] && fatal "\$1 input $ERROR_STDIN_NULL"

    butane_opts=(
        "--check"
        "--strict"
    )

    [ -n "$files_dir" ] && butane_opts+=("--files-dir=$files_dir")

    # shellcheck disable=SC2068
    if ! butane ${butane_opts[@]} <<< "$input"; then
        fatal "ignition check failed."
    fi

    info "Config ok"
    info "Config size: $(wc -c <<< "$input") bytes"
}

if [ "${__lib_logging_sourced:-}" != "true" ]; then
    declare -r __lib_logging="hack/lib/logging.sh"
    [ -f "$__lib_logging" ] || { printf '%s\n' "failed to find file: $__lib_logging" >&2; exit 1; }
    # shellcheck source=../logging.sh
    . "$__lib_logging"
fi
