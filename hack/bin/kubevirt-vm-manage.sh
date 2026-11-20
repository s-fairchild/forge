#!/bin/bash
# Create or update a KubeVirt VirtualMachine from a kustomize directory, along
# with the Secret its cloudInitConfigDrive volume reads the ignition config from
# (filled from a podman secret), in the current kubectl context. Deleting the VM
# (-d) is not implemented yet.

[[ "${XTRACE:-0}" -eq 1 ]] && set -x

# os/bk-bootstrap.sh, sourced below, sets errexit, nounset and pipefail.
set -o noclobber

usage() {
  set_script_name "${SCRIPT_NAME:-}:${FUNCNAME[0]}"
  cat <<USAGE >&2
Usage: ${0##*/} -k kustomize_dir (-c -i ignition_secret | -d) [-h]

Builds <kustomize_dir> with kustomize. The manifests must hold exactly one
Namespace, the VM's, and exactly one VirtualMachine with a cloudInitConfigDrive
volume, whose secretRef.name names the Kubernetes Secret for its ignition
config.

With -c, checks that the podman secret <ignition_secret> exists, applies the
manifests and waits for the Namespace's phase to be Active, then creates or
updates that Secret in it (server-side apply) from the podman secret's raw
contents, under the key userdata. Finally waits for the VM to become Ready.
Each wait gives up after 300s.

-d is not implemented yet.

Options:
  -k kustomize_dir       Path to the kustomize directory for the KubeVirt
                         VirtualMachine, relative to the current directory
                         (e.g. pkg/workloads/fcos-vm/overlays/staging).
                         (required)
  -i ignition_secret     Podman secret holding the compiled ignition JSON
                         (e.g. ignition-staging). (required with -c; not
                         needed with -d)
  -c                     Create or update the VM and its ignition Secret.
  -d                     Delete the VM. Not implemented yet; the script exits
                         with an error if it is given.
  -h                     Print this help message and exit.

Exactly one of -c or -d is required.
USAGE
}

# main()
#
# Parses and checks the options, builds the VirtualMachine kustomize directory,
# reads the VM's namespace from the Namespace in its manifests, and checks that
# the podman secret exists. Applies the manifests in a background job and
# waits for that namespace's phase to be Active, then reads the ignition
# Secret's name from the VirtualMachine's cloudInitConfigDrive volume
# (.secretRef.name), builds the Secret from the podman secret's raw contents
# and applies it there. The Secret can only be created once its namespace
# exists, which is why the manifests are applied first. Finally reads the VM's
# name from the manifests, waits for the background apply to finish, and waits
# for the VM to become Ready. Both waits use kube::kubectl_wait's default
# timeout of 300s.
#
# Globals:
#   SCRIPT_NAME                                Read; set_script_name makes it <name>_main.
#   __BASHKIT_CORE_BOOLEAN_TRUE                Read to set the -c/-d flag values.
# Arguments:
#   -k kustomize_dir       Path to the kustomize directory for the KubeVirt
#                          VirtualMachine. (required)
#   -i ignition_secret     Podman secret holding the compiled ignition JSON.
#                          (required with -c)
#   -c                     Create or update the VM and its ignition Secret.
#   -d                     Delete the VM. Not implemented yet; rejected.
#   -h                     Print usage and return 0.
#   Exactly one of -c or -d is required.
# Outputs:
#   Progress/log lines, including kubectl's output; usage text to stderr on -h
#   or an option error. An error and stack trace on any failure that returns
#   1; a failed wait logs only kubectl's output, at ERROR level. The ignition
#   payload only passes through pipes, never a variable or a command's
#   arguments, so XTRACE=1 doesn't trace it.
# Returns:
#   0 on success or -h. 1 on a bad or duplicate option, a missing -k, -c
#   without -i, or -d; a failed kustomize build or yq lookup; a missing
#   podman secret; or a failed Secret or background apply. A failed wait
#   exits the script with status 1 through errexit.
main() {
  set_script_name "${SCRIPT_NAME:-}:${FUNCNAME[0]}"
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  # TODO create a function to contain gathering options
  #   * Pass all variables to be collected as namerefs
  local kustomize_dir="" ignition_secret=""
  local create="" delete="" opt
  local -i OPTIND=1
  while getopts ':k:i:cdh' opt; do
    case "${opt}" in
      k)
        if ! core::is_option_arg_dup "${opt}" "${kustomize_dir}"; then
          usage
          return 1
        fi
        kustomize_dir="${OPTARG}"
        ;;
      c)
        if ! core::is_option_arg_dup "${opt}" "${create}"; then
          usage
          return 1
        fi
        create="${__BASHKIT_CORE_BOOLEAN_TRUE}"
        ;;
      d)
        if ! core::is_option_arg_dup "${opt}" "${delete}"; then
          usage
          return 1
        fi
        delete="${__BASHKIT_CORE_BOOLEAN_TRUE}"
        ;;
      i)
        if ! core::is_option_arg_dup "${opt}" "${ignition_secret}"; then
          usage
          return 1
        fi
        ignition_secret="${OPTARG}"
        ;;
      h) usage; return 0 ;;
      :)
        usage
        core::fail "$(basename "${0}") -${OPTARG} operand is required." || return
        ;;
      ?)
        usage
        core::fail "$(basename "${0}") -${OPTARG} option is unknown." || return
        ;;
    esac
  done
  shift $((OPTIND - 1))
  readonly kustomize_dir create delete ignition_secret
  log_debug "$(declare -p kustomize_dir create delete ignition_secret)"

  if [[ -n "${create}" ]] && [[ -z "${ignition_secret}" ]]; then
    usage
    core::fail "[-c -i] create mode requires the podman ignition payload secret name." || return
  elif [[ -n "${delete}" ]]; then
    usage
    core::fail "-d is not implemented yet." || return
  elif [[ -z "${kustomize_dir}" ]]; then
    usage
    core::fail "$(basename "${0}") -k [kustomize_dir] operand must be provided." || return
  fi

  log_info "Building manifests from kustomize directory ${kustomize_dir}"
  local manifests
  if ! manifests="$(kube::kustomize_build "${kustomize_dir}")"; then
    core::fail "kustomize build failed: ${kustomize_dir}" || return
  fi
  readonly manifests

  local namespace
  if ! namespace="$(core::yq eval \
      'select(.kind == "Namespace") | .metadata.name' \
      <<< "${manifests}")"; then

    core::fail "failed to get namespace from manifests." || return
  fi
  readonly namespace

  if ! podman::secret_exists "${ignition_secret}"; then
    core::fail "podman secret does not exist: ${ignition_secret}" || return
  fi

  # Apply in the background and wait only for the Namespace, which the Secret
  # below needs; the job is waited on after the Secret is applied. Background
  # jobs ignore SIGINT and SIGQUIT, so the job resets them; otherwise Ctrl-C
  # would kill this script and leave the job running.
  ( trap - INT QUIT; kube::kubectl_apply <<< "${manifests}" ) &
  local -ir vm_apply_pid="$!"
  # A Namespace has no Active condition, only .status.phase, so this waits on
  # a jsonpath. No quotes around it: kube::kubectl_wait passes this string to
  # kubectl as one argument, with no shell to strip them, and kubectl rejects
  # a quoted expression.
  kube::kubectl_wait -r "namespace/${namespace}" \
    -c "--for=jsonpath={.status.phase}=Active"

  local k8s_ignition_secret_name
  if ! k8s_ignition_secret_name="$(core::yq eval \
      'select(.kind == "VirtualMachine")
      | .spec.template.spec.volumes[]
      | select(has("cloudInitConfigDrive"))
      | .cloudInitConfigDrive.secretRef.name' \
      <<< "${manifests}")"; then

    core::fail "failed to get cloudInitConfigDrive secretRef name from 
                  manifests (k8s ignition payload secret reference)" \
      || return
  fi

  log_info "Applying Secret ${k8s_ignition_secret_name} in namespace ${namespace} from podman secret ${ignition_secret}"
  # Secret data values are base64: tojson re-serializes the ignition JSON as one
  # compact string, which @base64 encodes under the userdata key the
  # cloudInitConfigDrive volume reads.
  podman::secret_showsecret "${ignition_secret}" \
  | jq -c \
      --arg name "${k8s_ignition_secret_name}" \
      --arg ns "${namespace}" \
      '{
        apiVersion: "v1",
        kind: "Secret",
        metadata: {name: $name, namespace: $ns},
        data: {userdata: (tojson | @base64)}
      }' \
  | kube::kubectl_apply - --server-side \
    || {
      core::fail "Failed to create secret ${k8s_ignition_secret_name} in namespace ${namespace}" || return
    }

  local fcos_vm_name
  if ! fcos_vm_name="$(core::yq eval \
      'select(.kind == "VirtualMachine") | .metadata.name' \
      <<< "${manifests}")"; then
    core::fail "failed to get the VirtualMachine name from manifests." || return
  fi
  readonly fcos_vm_name
  log_debug "$(declare -p fcos_vm_name)"

  wait "${vm_apply_pid}" \
    || core::fail "kube::kubectl_apply exited $?" \
    || return

  kube::kubectl_wait -n "${namespace}" \
     -c "--for=condition=Ready" \
     -r "virtualmachines/${fcos_vm_name}"
}

# shellcheck source=../vendor/bashkit/local/lib/bashkit/os/bk-bootstrap.sh
. "${BASH_SOURCE[0]%/*}/../vendor/bashkit/local/lib/bashkit/os/bk-bootstrap.sh"

# shellcheck source=../vendor/bash-logger/logging.sh
. /dev/null
# shellcheck source=../vendor/bashkit/local/lib/bashkit/core/logger-utils.sh
. /dev/null
import core/logger-utils.sh
# shellcheck source=../vendor/bashkit/local/lib/bashkit/core/yq-utils.sh
. /dev/null
import core/yq-utils.sh
# shellcheck source=../vendor/bashkit/local/lib/bashkit/podman/podman-secret.sh
. /dev/null
import podman/podman-secret.sh
# shellcheck source=../vendor/bashkit/local/lib/bashkit/kube/kube.sh
. /dev/null
import kube/kube.sh

core::logger_init --name "$(basename "$0")"

main "$@"
