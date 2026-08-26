# shellcheck shell=bash

declare -r __hack_lib_yq_sourced="true"

# yq()
#
# Thin podman wrapper around docker.io/mikefarah/yq:4.53.2.
# Mounts the current working directory as /workdir inside the container and
# forwards all YQ_* environment variables so callers can pass values via the
# environment without shell quoting issues.
yq() {
    # 1>&2: this function's stdout is its return channel (the containerized yq's output),
    # captured via `$(...)` by every caller -- any console-level log write on stdout here would
    # corrupt it.
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))" 1>&2
    local -r log_level="${PODMAN_LOG_LEVEL:-warn}"
    local -r image="docker.io/mikefarah/yq:4.53.2"
    # local -Ix "${!YQ_*}"

    podman run \
        --userns keep-id \
        --env 'YQ_*' \
        --log-level "$log_level" \
        -i \
        --rm \
        -v "${PWD}:/workdir":O \
        --workdir /workdir \
        "$image" \
            --exit-status=1 \
            "$@"
}

if [ "${__bash_logger_adapter_sourced:-}" != "true" ]; then
    declare __bash_logger_adapter_path="hack/vendor/bash-logger-adapter/adapter.sh"
    [ -f "$__bash_logger_adapter_path" ] || { printf '%s\n' "failed to find file: $__bash_logger_adapter_sourced" >&2; exit 1; }
    # shellcheck source=../vendor/bash-logger-adapter/adapter.sh
    . "$__bash_logger_adapter_path"
    unset __bash_logger_adapter_path
fi
