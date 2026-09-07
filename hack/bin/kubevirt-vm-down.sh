#!/bin/bash
# Delete a KubeVirt VirtualMachine manifest from the current kubectl context.

[[ "${XTRACE:-0}" -eq 1 ]] && set -x

set -o nounset \
  -o errexit \
  -o pipefail \
  -o noclobber \
  -o hashall

usage() {
  cat <<USAGE >&2
Usage: ${0##*/} -f vm_manifest [-v] [-q] [-h]

Deletes the KubeVirt VirtualMachine defined by <vm_manifest> (--ignore-not-found, so
this is safe to re-run). Leaves the k3d cluster and its KubeVirt/CDI install running --
use k3d-cluster-down.sh to tear those down.

Options:
  -f vm_manifest   Path to the KubeVirt VirtualMachine manifest to delete. (required)
  -v               Enable verbose/DEBUG-level logging for this invocation, overriding
                   VERBOSE/DEBUG.
  -q               Suppress console logging for this invocation, overriding QUIET.
  -h               Print this help message and exit.
USAGE
}

# main()
#
# Deletes the KubeVirt VirtualMachine manifest passed via -f from the current kubectl
# context.
#
# Globals:
#   __bash_logger_adapter_env_log_level   Read to apply CLI-flag logging overrides.
# Arguments:
#   -f vm_manifest   Path to the KubeVirt VirtualMachine manifest to delete. (required)
#   -v               Enable verbose/DEBUG-level logging for this invocation.
#   -q               Suppress console logging for this invocation.
#   -h               Print usage and return 0.
# Outputs:
#   Writes progress/log messages; usage text to stderr on -h/bad options.
# Returns:
#   0 on success; calls fatal (non-zero exit) on any failure.
main() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  local vm_manifest="" opt
  local -i OPTIND=1 cli_verbose=0 cli_quiet=0
  while getopts ':f:vqh' opt; do
    case "${opt}" in
      f)
        core::is_option_arg_dup "${opt}" "${vm_manifest}"
        vm_manifest="${OPTARG}"
        ;;
      v)
        cli_verbose=1
        ;;
      q)
        cli_quiet=1
        ;;
      h)
        usage
        exit 0
        ;;
      :)
        usage
        fatal "-${OPTARG} ${ERROR_OPTION_REQUIRED}"
        ;;
      ?)
        usage
        fatal "-${OPTARG} ${ERROR_OPTION_UNKNOWN}"
        ;;
    esac
  done
  shift $((OPTIND - 1))

  bash_logger_adapter_apply_overrides "${cli_verbose}" \
                                       "${cli_quiet}" \
                                       "${__bash_logger_adapter_env_log_level}"

  [[ -n "${vm_manifest}" ]] || { usage; fatal "-f ${ERROR_OPTION_REQUIRED}"; }
  [[ -f "${vm_manifest}" ]] || { usage; fatal "${ERROR_FILE_NOT_FOUND}: ${vm_manifest}"; }
  local -r vm_manifest
  debug "$(declare -p vm_manifest)"

  info "Deleting VirtualMachine manifest ${vm_manifest}"
  if ! kubectl delete -f "${vm_manifest}" --ignore-not-found; then
    fatal "kubectl delete -f ${vm_manifest} failed"
  fi
}

if [[ "${__bash_logger_adapter_sourced:-}" != "true" ]]; then
  declare __bash_logger_adapter_path="hack/vendor/bash-logger-adapter/adapter.sh"
  [[ -f "${__bash_logger_adapter_path}" ]] || { printf '%s\n' "failed to find file: ${__bash_logger_adapter_path}" >&2; exit 1; }
  # shellcheck source=../vendor/bash-logger-adapter/adapter.sh
  . "${__bash_logger_adapter_path}"
  unset __bash_logger_adapter_path
fi

if [[ "${__bashkit_core_sourced:-}" != "true" ]]; then
  declare __bashkit_core="hack/vendor/bashkit/local/lib/bashkit/core/contract-utils.sh"
  [[ -f "${__bashkit_core}" ]] || fatal "${ERROR_FILE_NOT_FOUND}: ${__bashkit_core}"
  # shellcheck source=../vendor/bashkit/local/lib/bashkit/core/contract-utils.sh
  . "${__bashkit_core}"
  unset __bashkit_core
fi

main "$@"
