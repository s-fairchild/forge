# shellcheck shell=bash

declare -r __lib_podman_sourced="true"

declare -F log_fatal > /dev/null 2>&1 || fatal() { printf '%s\n' "${1:-}" >&2; exit 1; }

if [ "${__lib_podman_run_sourced:-}" != "true" ]; then
    declare __lib_podman_run="hack/lib/podman/podman-container.sh"
    [ -f "$__lib_podman_run" ] || log_fatal "file not found: $__lib_podman_run"
    # shellcheck source=podman-container.sh
    . "$__lib_podman_run"
    unset __lib_podman_run
fi

if [ "${__lib_podman_secret_sourced:-}" != "true" ]; then
    declare __lib_podman_secret="hack/lib/podman/podman-secret.sh"
    [ -f "$__lib_podman_secret" ] || log_fatal "file not found: $__lib_podman_secret"
    # shellcheck source=podman-secret.sh
    . "$__lib_podman_secret"
    unset __lib_podman_secret
fi

if [ "${__lib_podman_volume_sourced:-}" != "true" ]; then
    declare __lib_podman_volume="hack/lib/podman/podman-volume.sh"
    [ -f "$__lib_podman_volume" ] || log_fatal "file not found: $__lib_podman_volume"
    # shellcheck source=podman-volume.sh
    . "$__lib_podman_volume"
    unset __lib_podman_volume
fi
