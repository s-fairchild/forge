# hack/lib/ignition/butane.sh
#
# shellcheck shell=bash

declare -r __hack_lib_ignition_butane_sourced="true"
declare -r __BUTANE_WORKDIR="/data"

usage_butane() {
    cat <<USAGE >&2
Usage: butane [-s secret]... [-h] [butane_arg...]

Runs butane in a container with image quay.io/coreos/butane:release.

Options:
    -s secret  podman secret spec passed verbatim to \`podman run --secret\`
               (e.g. "my-key,type=mount,target=/data/files/secrets/my-key").
               May be specified multiple times.
    -h         Print this usage message and exit.

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
#                 (e.g. "my-key,type=mount,target=/data/files/secrets/my-key").
#                 Repeatable.
#   * $@        - remaining args are passed to the butane container.
#
# Environment:
#   * PODMAN_LOG_LEVEL   - string; podman run log level (default: warn).
#   * BUTANE_VOLUME_MOUNT - string; host directory to mount as the container workdir.
butane() {
    # 1>&2 on every log call in this function: stdout is butane()'s return channel (its callers,
    # e.g. ignition_gen(), pass it straight through as their own compiled-JSON output), so any
    # console-level log write on stdout here would corrupt that output.
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))" 1>&2

    local -a podman_run_options=()
    local opt workdir_mount_src
    local -i OPTIND=1
    while getopts ':s:m:h' opt; do
        case "$opt" in
            s)
                podman_run_options+=("--secret=${OPTARG}")
                ;;
            m)
                if [ -n "${workdir_mount_src:-}" ]; then
                    usage_butane
                    error "-${opt} ${ERROR_OPTION_ARG_DUP}"
                    return 1
                fi
                workdir_mount_src="${OPTARG}"
                local -r workdir_mount_src
                ;;
            h)
                usage_butane
                return 0
                ;;
            :)
                usage_butane
                error "-${OPTARG} $ERROR_OPTION_REQUIRED"
                return 1
                ;;
            ?)
                usage_butane
                error "-${OPTARG} $ERROR_OPTION_UNKNOWN"
                return 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    [ -n "${PODMAN_LOG_LEVEL:-}" ] && podman_run_options+=("--log-level=$PODMAN_LOG_LEVEL")
    if [ -n "${workdir_mount_src:-}" ]; then
        [ -d "${workdir_mount_src}" ] || { error "${ERROR_DIR_NOT_FOUND}: ${workdir_mount_src}"; return 1; }

        podman_run_options+=(
            "--mount=type=bind,src=${workdir_mount_src},target=${__BUTANE_WORKDIR},bind-propagation=rslave,no-dereference,ro=true"
            "--security-opt=label=disable"
        )
    fi

    podman_run_options+=(
        "-i"
        "--rm"
        "--env='BU_*'"
        "--env='BUTANE_*'"
        "--workdir=${__BUTANE_WORKDIR}"
    )
    local -r image="quay.io/coreos/butane:release"
    log_sensitive "$(declare -p image podman_run_options __BUTANE_WORKDIR)" 1>&2
    log_sensitive "${FUNCNAME[0]}() options: $*" 1>&2

    # shellcheck disable=SC2068
    podman run \
           ${podman_run_options[@]} \
           "$image" \
           "$@"
}

export -f butane

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
