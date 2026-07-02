# hack/lib/ignition/butane.sh
#
# shellcheck shell=bash

declare -r __hack_lib_ignition_butane_sourced="true"
declare -r __BUTANE_WORKDIR="/data"
declare -r __BUTANE_FILES_DIR="files"

usage_butane() {
    cat <<USAGE >&2
Usage: butane [-s secret]... [butane_arg...]

Runs butane in a container with image quay.io/coreos/butane:release.

Options:
    -s secret  podman secret spec passed verbatim to \`podman run --secret\`
               (e.g. "mykey,type=mount,target=/data/files/secrets/mykey").
               May be specified multiple times.

Remaining arguments are passed through to the butane container.

Environment:
    PODMAN_LOG_LEVEL     podman run log level. (default: warn)
    BUTANE_VOLUME_MOUNT  host directory to mount as the container workdir. (default: \$PWD)
USAGE
}

# butane()
#
# Runs butane in a container with image quay.io/coreos/butane:release.
#
# Options:
#   * -s <spec> - podman secret spec passed verbatim to `podman run --secret`
#                 (e.g. "mykey,type=mount,target=/data/files/secrets/mykey").
#                 Repeatable.
#   * $@        - remaining args are passed to the butane container.
#
# Environment:
#   * PODMAN_LOG_LEVEL   - string; podman run log level (default: warn).
#   * BUTANE_VOLUME_MOUNT - string; host directory to mount as the container workdir.
butane() {
    debug "Starting ${FUNCNAME[0]}()"

    local -a podman_run_options=()
    local opt OPTIND=1
    while getopts ':s:' opt; do
        case "$opt" in
            s)
                debug "Adding --secret=$OPTARG"
                podman_run_options+=("--secret=$OPTARG")
                ;;
            :)
                usage_butane
                fatal "-${OPTARG} $ERROR_OPTION_REQUIRED"
                ;;
            ?)
                usage_butane
                fatal "-${OPTARG} $ERROR_OPTION_UNKNOWN"
                ;;
        esac
    done
    shift $((OPTIND - 1))

    [ -n "${PODMAN_LOG_LEVEL:-}" ] && podman_run_options+=("--log-level=$PODMAN_LOG_LEVEL")

    local -a podman_run_options=(
        "-i"
        "--rm"
        "--env='BU_*'"
        "--security-opt=label=disable"
        "--mount=type=bind,src=${BUTANE_VOLUME_MOUNT:-$PWD},target=$__BUTANE_WORKDIR,bind-propagation=rslave,no-dereference,ro=true"
        "--workdir=$__BUTANE_WORKDIR"
    )

    debug "$(declare -p __BUTANE_WORKDIR)"
    debug "$(declare -p podman_run_options)"
    debug "butane options: $*"
    local -r image="quay.io/coreos/butane:release"
    debug "$(declare -p image)"

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
    if ! butane -- ${butane_opts[@]} <<< "$input"; then
        fatal "ignition check failed."
    fi

    info "Config ok"
    info "Config size: $(wc -c <<< "$input") bytes"
}

if [ "${__bash_utils_base_config_logging_sourced:-}" != "true" ]; then
    declare -r __bash_utils_base_config_logging="hack/vendor/bash-utils/lib/base-config-logging.sh"
    [ -f "$__bash_utils_base_config_logging" ] || { printf '%s\n' "failed to find file: $__bash_utils_base_config_logging" >&2; exit 1; }
    # shellcheck source=../../vendor/bash-utils/lib/base-config-logging.sh
    . "$__bash_utils_base_config_logging"
fi
