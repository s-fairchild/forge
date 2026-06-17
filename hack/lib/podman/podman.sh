# shellcheck shell=bash

declare -r __lib_podman_sourced="true"

if [ "${__lib_logging_sourced:-}" != "true" ]; then
    declare -r __lib_logging="hack/lib/logging.sh"
    [ -f "$__lib_logging" ] || { printf '%s\n' "failed to find file: $__lib_logging" >&2; exit 1; }
    # shellcheck source=../logging.sh
    . "$__lib_logging"
fi

if [ "${__lib_podman_run_sourced:-}" != "true" ]; then
    declare -r __lib_podman_run="hack/lib/podman/podman-run.sh"
    [ -f "$__lib_podman_run" ] || fatal "$ERROR_FILE_NOT_FOUND: $__lib_podman_run"
    # shellcheck source=podman-run.sh
    . "$__lib_podman_run"
fi

if [ "${__lib_podman_volume_sourced:-}" != "true" ]; then
    declare -r __lib_podman_volume="hack/lib/podman/podman-volume.sh"
    [ -f "$__lib_podman_volume" ] || fatal "$ERROR_FILE_NOT_FOUND: $__lib_podman_volume"
    # shellcheck source=podman-volume.sh
    . "$__lib_podman_volume"
fi

if [ "${__lib_podman_secret_sourced:-}" != "true" ]; then
    declare -r __lib_podman_secret="hack/lib/podman/podman-secret.sh"
    [ -f "$__lib_podman_secret" ] || fatal "$ERROR_FILE_NOT_FOUND: $__lib_podman_secret"
    # shellcheck source=podman-secret.sh
    . "$__lib_podman_secret"
fi
