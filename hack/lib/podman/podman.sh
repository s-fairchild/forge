# hack/lib/podman/podman.sh
#
# Umbrella loader for the podman-container/podman-secret/podman-volume library files.
# shellcheck shell=bash

declare -r __hack_lib_podman_sourced="true"

declare -F fatal > /dev/null 2>&1 || fatal() { printf '%s\n' "${1:-}" >&2; exit 1; }

if [[ "${__hack_lib_podman_container_sourced:-}" != "true" ]]; then
  declare __lib_podman_run="hack/lib/podman/podman-container.sh"
  [[ -f "${__lib_podman_run}" ]] || fatal "file not found: ${__lib_podman_run}"
  # shellcheck source=podman-container.sh
  . "${__lib_podman_run}"
  unset __lib_podman_run
fi

if [[ "${__hack_lib_podman_secret_sourced:-}" != "true" ]]; then
  declare __lib_podman_secret="hack/lib/podman/podman-secret.sh"
  [[ -f "${__lib_podman_secret}" ]] || fatal "file not found: ${__lib_podman_secret}"
  # shellcheck source=podman-secret.sh
  . "${__lib_podman_secret}"
  unset __lib_podman_secret
fi

if [[ "${__hack_lib_podman_volume_sourced:-}" != "true" ]]; then
  declare __lib_podman_volume="hack/lib/podman/podman-volume.sh"
  [[ -f "${__lib_podman_volume}" ]] || fatal "file not found: ${__lib_podman_volume}"
  # shellcheck source=podman-volume.sh
  . "${__lib_podman_volume}"
  unset __lib_podman_volume
fi
