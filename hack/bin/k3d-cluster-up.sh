#!/bin/bash
# Idempotently create a k3d cluster from a config file and install KubeVirt + CDI onto it.

[[ "${XTRACE:=0}" -eq 1 ]] && set -x

set -o nounset \
    -o errexit \
    -o pipefail \
    -o noclobber \
    -o hashall

usage() {
  cat <<USAGE >&2
Usage: ${0##*/} -f k3d_config [-v] [-q] [-h]

Idempotently creates a k3d cluster from <k3d_config> (k3d.io/v1alpha5 Simple
config; the cluster name is read from its .metadata.name), then installs
KubeVirt and CDI (Containerized Data Importer) onto it and waits for both to
become Available.

k3d itself merges the new cluster's kubeconfig into the default kubeconfig
and switches the current context, so subsequent kubectl/helm calls need no
extra wiring.

Options:
  -f k3d_config   Path to a k3d.io/v1alpha5 Simple cluster config
                  (e.g. deploy/k3d/staging.yaml). (required)
  -v              Enable verbose/DEBUG-level logging for this invocation,
                  overriding VERBOSE/DEBUG.
  -q              Suppress console logging for this invocation, overriding
                  QUIET.
  -h              Print this help message and exit.
USAGE
}

# main()
#
# Idempotently creates a k3d cluster from a config file's .metadata.name and
# installs KubeVirt + CDI onto it.
#
# Globals:
#   __bash_logger_adapter_env_log_level   Read to apply logging overrides.
# Arguments:
#   -f config   Path to a k3d.io/v1alpha5 Simple cluster config. (required)
#   -v          Enable verbose/DEBUG-level logging for this invocation.
#   -q          Suppress console logging for this invocation.
#   -h          Print usage and exit 0.
# Outputs:
#   Writes progress/status log lines; usage text to stderr on -h/bad options.
# Returns:
#   0 on success (including when the cluster already existed); calls fatal
#   (non-zero exit) on option-parsing failure or k3d cluster create failure.
main() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  local config="" opt
  local -i OPTIND=1 cli_verbose=0 cli_quiet=0
  while getopts ':f:vqh' opt; do
    case "${opt}" in
      f)
        core::is_option_arg_dup "${opt}" "${config}"
        config="${OPTARG}"
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

  [[ -n "${config}" ]] || { usage; fatal "-f ${ERROR_OPTION_REQUIRED}"; }
  [[ -f "${config}" ]] || { usage; fatal "${ERROR_FILE_NOT_FOUND}: ${config}"; }
  local -r config
  debug "$(declare -p config)"

  local cluster_name
  cluster_name="$(yq eval '.metadata.name' "${config}")" \
    || fatal "failed to read .metadata.name from ${config}"
  local -r cluster_name
  [[ -n "${cluster_name}" ]] && [[ "${cluster_name}" != "null" ]] \
    || fatal "${config} has no .metadata.name"

  if k3d cluster list "${cluster_name}" >/dev/null 2>&1; then
    info "k3d cluster '${cluster_name}' already exists"
  else
    info "Creating k3d cluster '${cluster_name}' from ${config}"
    k3d cluster create --config "${config}" || fatal "k3d cluster create failed"
  fi

  kubevirt_install
  cdi_install
}

if [[ "${__bash_logger_adapter_sourced:-}" != "true" ]]; then
  declare __bash_logger_adapter_path="hack/vendor/bash-logger-adapter/adapter.sh"
  [[ -f "${__bash_logger_adapter_path}" ]] \
    || { printf '%s\n' "failed to find file: ${__bash_logger_adapter_path}" >&2; exit 1; }
  # shellcheck source=../vendor/bash-logger-adapter/adapter.sh
  . "${__bash_logger_adapter_path}"
  unset __bash_logger_adapter_path
fi

if [[ "${__bashkit_core_sourced:-}" != "true" ]]; then
  declare __bashkit_core="hack/vendor/bashkit/local/lib/bashkit/core/contract-utils.sh"
  [[ -f "${__bashkit_core}" ]] \
    || fatal "${ERROR_FILE_NOT_FOUND}: ${__bashkit_core}"
  # shellcheck source=../vendor/bashkit/local/lib/bashkit/core/contract-utils.sh
  . "${__bashkit_core}"
  unset __bashkit_core
fi

if [[ "${__hack_lib_yq_sourced:-}" != "true" ]]; then
  declare __hack_lib_yq="hack/lib/yq.sh"
  [[ -f "${__hack_lib_yq}" ]] || fatal "${ERROR_FILE_NOT_FOUND}: ${__hack_lib_yq}"
  # shellcheck source=../lib/yq.sh
  . "${__hack_lib_yq}"
  unset __hack_lib_yq
fi

if [[ "${__hack_lib_kubevirt_sourced:-}" != "true" ]]; then
  declare __hack_lib_kubevirt="hack/lib/kubevirt/kubevirt.sh"
  [[ -f "${__hack_lib_kubevirt}" ]] || fatal "${ERROR_FILE_NOT_FOUND}: ${__hack_lib_kubevirt}"
  # shellcheck source=../lib/kubevirt/kubevirt.sh
  . "${__hack_lib_kubevirt}"
  unset __hack_lib_kubevirt
fi

main "$@"
