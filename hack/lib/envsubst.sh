# hack/lib/envsubst.sh
#
# TODO move this into bash-helpers repository
# shellcheck shell=bash

declare -r __hack_lib_envsubst_sourced="true"

# envsubst()
#
# Thin podman wrapper around docker.io/steve51516/envsubst:latest. Forwards
# all ENVSUBST_* environment variables and, when set, mounts every entry of
# ENVSUBST_SECRET_MOUNTS as a podman env-type secret.
#
# Globals:
#   PODMAN_LOG_LEVEL          Optional. podman run log level. (default: warn)
#   ENVSUBST_SECRET_MOUNTS    Optional array of secret names to mount as
#                             env-type secrets.
# Arguments:
#   $@   All arguments are passed through to the envsubst container.
# Outputs:
#   Writes the containerized envsubst's stdout/stderr.
# Returns:
#   The container's exit status.
envsubst() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  local -r log_level="${PODMAN_LOG_LEVEL:-warn}"
  local -r image="docker.io/steve51516/envsubst:latest"

  local -a podman_run_options=(
    --rm
    -i
    --log-level "${log_level}"
    --env 'ENVSUBST_*'
  )

  if [[ -v ENVSUBST_SECRET_MOUNTS ]]; then
    mapfile -O "${#podman_run_options[@]}" \
      podman_run_options \
      < <(printf -- "--secret %s,type=env\n" "${ENVSUBST_SECRET_MOUNTS[@]}")
  fi

  podman run \
    "${podman_run_options[@]}" \
    "${image}" \
    -no-digit \
    -no-unset \
    -no-empty \
    "$@"
}

# Allow Makefile and other programs access
export -f envsubst

if [[ "${__bash_logger_adapter_sourced:-}" != "true" ]]; then
  declare __bash_logger_adapter_path="hack/vendor/bash-logger-adapter/adapter.sh"
  [[ -f "${__bash_logger_adapter_path}" ]] || { printf '%s\n' "failed to find file: ${__bash_logger_adapter_path}" >&2; exit 1; }
  # shellcheck source=../vendor/bash-logger-adapter/adapter.sh
  . "${__bash_logger_adapter_path}"
  unset __bash_logger_adapter_path
fi
