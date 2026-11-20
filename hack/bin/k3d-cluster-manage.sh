#!/bin/bash
# Create a k3d cluster from a config file and install KubeVirt + CDI onto it, or
# delete that cluster.

[[ "${XTRACE:=0}" -eq 1 ]] && set -x

set -euCho pipefail

usage() {
  cat <<USAGE >&2
Usage: ${0##*/} -f k3d_config (-c | -d) [-h]

The cluster name is read from <k3d_config>'s .metadata.name (a k3d.io/v1alpha5
Simple config). k3d runs through sudo.

With -c, idempotently creates the cluster from <k3d_config>, merges its
kubeconfig into ~/.kube/config (owned by you, with the server address set to
the config's .kubeAPI.hostIP), then installs KubeVirt and CDI (Containerized
Data Importer) onto it in parallel and waits for both to become Available.

With -d, deletes the cluster. It is an error if the cluster doesn't exist.

Options:
  -f k3d_config   Path to a k3d.io/v1alpha5 Simple cluster config, relative
                  to the current directory (e.g. deploy/k3d/staging.yaml).
                  (required)
  -c              Create the cluster and install KubeVirt and CDI.
  -d              Delete the cluster.
  -h              Print this help message and exit.

Exactly one of -c or -d is required.
USAGE
}

# main()
#
# Reads the cluster name from the config's .metadata.name, then either creates the
# cluster, merges its kubeconfig into ~/.kube/config, and deploys KubeVirt + CDI
# onto it in parallel (-c), or deletes the cluster (-d).
#
# Globals:
#   HOME                                   Read for the kubeconfig path.
#   SCRIPT_NAME                            Read to scope the logger's script name.
#   __BASHKIT_CORE_BOOLEAN_TRUE            Read to set the -c/-d flag values.
# Arguments:
#   -f config   Path to a k3d.io/v1alpha5 Simple cluster config. (required)
#   -c          Create the cluster and deploy KubeVirt and CDI.
#   -d          Delete the cluster.
#   -h          Print usage and exit 0.
# Outputs:
#   Writes progress/status log lines; usage text to stderr on -h/bad options.
# Returns:
#   0 on success, including when -c finds the cluster already exists. Exits 1 on a
#   duplicate option and calls log_fatal (non-zero exit) on any other option error.
#   1 if the cluster name can't be read, a k3d step or the kubeconfig merge fails,
#   the KubeVirt or CDI deploy fails (reported after both have finished), or -d
#   finds no such cluster.
main() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  set_script_name "${SCRIPT_NAME:-}:${FUNCNAME[0]}"

  local config="" opt create="" delete=""
  local -i OPTIND=1
  while getopts ':f:c :dh' opt; do
    case "${opt}" in
      f)
        core::is_option_arg_dup "${opt}" "${config}" || { usage; exit 1; }
        readonly config="${OPTARG}"
        ;;
      c)
        core::is_option_arg_dup "${opt}" "${create}" || { usage; exit 1; }
        readonly create="${__BASHKIT_CORE_BOOLEAN_TRUE}"
        ;;
      d)
        core::is_option_arg_dup "${opt}" "${delete}" || { usage; exit 1; }
        readonly delete="${__BASHKIT_CORE_BOOLEAN_TRUE}"
        ;;
      h) usage; exit 0; ;;
      :) usage; log_fatal "$(basename "${0}") -${OPTARG} operand must be provided."; ;;
      ?) usage; log_fatal "$(basename "${0}") -${OPTARG} option is unknown."; ;;
    esac
  done
  shift $((OPTIND - 1))

  if [[ -n "${create}" ]] && [[ -n "${delete}" ]]; then
    usage
    log_fatal "-c and -d are mutually exclusive. Only one can be provided."
  elif [[ -z "${create}" ]] && [[ -z "${delete}" ]]; then
    usage
    log_fatal "either -c or -d must be provided."
  fi

  [[ -n "${config}" ]] || { usage; log_fatal "-f option must be provided."; }
  readonly config
  log_debug "$(declare -p config)"

  local cluster_name
  cluster_name="$(k3d::get_cluster_name_from_config "${config}")" || {
    core::fail "Failed to retrieve k3d cluster name from ${config}" || return
  }

  if [[ -n "${create}" ]]; then
    # shellcheck source=../lib/kubevirt/kubevirt.sh
    . "${BASH_SOURCE[0]%/*}/../lib/kubevirt/kubevirt.sh"

    k3d::cluster_create "${cluster_name}" \
      "${config}" \
      || return
    k3d::merge_kubeconfig_with_user "${config}" \
      "${HOME}/.kube/config" \
      || return

    # KubeVirt and CDI don't depend on each other, so deploy them in
    # parallel. virt-template-controller waits for CDI's API group, then
    # retries its DataVolume watch until the CDI CR registers that CRD.
    # Background jobs ignore SIGINT and SIGQUIT, so each job resets them;
    # otherwise Ctrl-C would kill this script and leave the jobs running.
    ( trap - INT QUIT; kubevirt::deploy ) &
    local -ri kubevirt_pid="$!"
    ( trap - INT QUIT; kubevirt::cdi_deploy ) &
    local -ri cdi_pid="$!"

    local -i kubevirt_rc=0 cdi_rc=0
    wait "${kubevirt_pid}" || kubevirt_rc="$?"
    wait "${cdi_pid}" || cdi_rc="$?"

    if (( kubevirt_rc != 0 || cdi_rc != 0 )); then
      local msg
      printf -v msg \
        'kubevirt::deploy exited %d, kubevirt::cdi_deploy exited %d' \
        "${kubevirt_rc}" \
        "${cdi_rc}"

      core::fail "${msg}" || return
    fi
  elif [[ -n "${delete}" ]]; then
    k3d::cluster_delete "${cluster_name}" || return
  fi
}

# shellcheck source=../lib/git/submodule.sh
. "${BASH_SOURCE[0]%/*}/../lib/git/submodule.sh"
git::submodule_require "${BASH_SOURCE[0]%/*}/../vendor/bash-logger/logging.sh"
git::submodule_require "${BASH_SOURCE[0]%/*}/../vendor/bashkit/local/lib/bashkit/core/logger-utils.sh"

# shellcheck source=../vendor/bashkit/local/lib/bashkit/os/bk-bootstrap.sh
. "${BASH_SOURCE[0]%/*}/../vendor/bashkit/local/lib/bashkit/os/bk-bootstrap.sh"

# shellcheck source=../vendor/bashkit/local/lib/bashkit/core/logger-utils.sh
. "${BASH_SOURCE[0]%/*}/../vendor/bashkit/local/lib/bashkit/core/logger-utils.sh"
# shellcheck source=../vendor/bash-logger/logging.sh
. /dev/null
core::logger_init --name "$(basename "$0")"

# shellcheck source=../vendor/bashkit/local/bin/yq
. "${BASH_SOURCE[0]%/*}/../vendor/bashkit/local/bin/yq"

# shellcheck source=../lib/k3d/k3d.sh
. "${BASH_SOURCE[0]%/*}/../lib/k3d/k3d.sh"

main "$@"
