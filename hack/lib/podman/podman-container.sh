# hack/lib/podman/podman-container.sh
#
# Runs a nested `podman` CLI inside a container, with the host's rootless podman
# graphroot volume mounted so the nested podman shares its storage.
# shellcheck shell=bash

declare -r __hack_lib_podman_container_sourced="true"

declare -r __PODMAN_CONTAINER_USER="podman"
declare -r __PODMAN_CONTAINER_GRAPHROOT_USER_PODMAN_VOLUME_NAME="graphroot-user-podman"
declare -r __PODMAN_CONTAINER_GRAPHROOT_USER_PODMAN_TARGET="/home/podman/.local/share/containers/storage"

declare -r __PODMAN_CONTAINER_VOLUME_GRAPHROOT_USER_PODMAN="graphroot-user-podman"
declare -r __PODMAN_CONTAINER_VOLUME_TARGET_GRAPHROOT_USER_PODMAN="/home/podman/.local/share/containers/storage"

# podman_container()
#
# Runs `podman <args...>` inside a registry.redhat.io/ubi10/podman container, with the
# graphroot-user-podman volume mounted so the nested podman shares the host's rootless
# podman storage.
#
# Arguments:
#   $@   Arguments passed through verbatim to the containerized `podman` CLI.
# Outputs:
#   Writes the nested podman invocation's stdout/stderr.
# Returns:
#   The nested podman invocation's exit status.
podman_container() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  local -a podman_options=(
    "--user=${__PODMAN_CONTAINER_USER}"
    "--security-opt=label=disable"
    "--volume=${__PODMAN_CONTAINER_VOLUME_GRAPHROOT_USER_PODMAN}:${__PODMAN_CONTAINER_VOLUME_TARGET_GRAPHROOT_USER_PODMAN}"
    "--rm"
    "-i"
  )
  local -r image="registry.redhat.io/ubi10/podman:latest"

  podman run \
    "${podman_options[@]}" \
    "${image}" \
    podman \
    "$@"
}

if [[ "${__bash_logger_adapter_sourced:-}" != "true" ]]; then
  declare __bash_logger_adapter_path="hack/vendor/bash-logger-adapter/adapter.sh"
  [[ -f "${__bash_logger_adapter_path}" ]] || { printf '%s\n' "failed to find file: ${__bash_logger_adapter_path}" >&2; exit 1; }
  # shellcheck source=../../vendor/bash-logger-adapter/adapter.sh
  . "${__bash_logger_adapter_path}"
  unset __bash_logger_adapter_path
fi
