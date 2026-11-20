# shellcheck shell=bash
#
# kubevirt::deploy: applies the pinned KubeVirt operator and CR and waits for both
# to become Available.

set -euCho pipefail

###############################
### Configuration Constants ###
###############################

# Version pins live in the referenced kustomization.yaml files' resources: URLs, not here --
# see pkg/operators/kubevirt/{operator,cr}/kustomization.yaml and
# pkg/operators/cdi/{operator,cr}/kustomization.yaml.
[[ -v __KUBEVIRT_KUSTOMIZATION_DEFAULT ]] \
  || readonly __KUBEVIRT_KUSTOMIZATION_DEFAULT="pkg/operators/kubevirt"
[[ -v __KUBEVIRT_NAMESPACE ]] \
  || readonly __KUBEVIRT_NAMESPACE="kubevirt"
[[ -v __KUBEVIRT_DEPLOYMENT_OPERATOR ]] \
  || readonly __KUBEVIRT_DEPLOYMENT_OPERATOR="deployment/virt-operator"
[[ -v __KUBEVIRT_CR_KUBEVIRT ]] \
  || readonly __KUBEVIRT_CR_KUBEVIRT="kv/kubevirt"

# kubevirt::deploy([kustomize_dir])
#
# Idempotently applies the pinned KubeVirt operator and CR (kubectl apply is itself
# idempotent) against the current kubeconfig context, building each with kustomize,
# and waits for the operator Deployment and the KubeVirt CR to become Available. The
# operator and CR are applied (and waited on) as two separate steps because the CR's
# CRD is only registered once the operator is running -- applying both at once races
# the CRD not existing yet.
#
# Globals:
#   __KUBEVIRT_KUSTOMIZATION_DEFAULT   Read as the default <kustomize_dir>.
#   __KUBEVIRT_NAMESPACE               Read as the namespace to wait in.
#   __KUBEVIRT_DEPLOYMENT_OPERATOR     Read as the operator resource to wait on.
#   __KUBEVIRT_CR_KUBEVIRT             Read as the CR resource to wait on.
# Arguments:
#   $1   Optional. Directory holding the operator/ and cr/ kustomizations.
#        Defaults to pkg/operators/kubevirt.
# Outputs:
#   Log lines from kube::kustomize_build_apply and kube::kubectl_wait; an error and
#   stack trace if <kustomize_dir> isn't a directory.
# Returns:
#   1 if <kustomize_dir> isn't a directory; otherwise the status of the first apply
#   or wait that fails, or 0.
# shellcheck disable=SC2120  # callers pass no arguments and rely on the defaults
kubevirt::deploy() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  local -r kustomize_dir="${1:-$__KUBEVIRT_KUSTOMIZATION_DEFAULT}"

  if [[ ! -d "${kustomize_dir}" ]]; then
    core::fail "kustomize dir not found: ${kustomize_dir}" || return
  fi

  kube::kustomize_build_apply "${kustomize_dir}/operator" || return
  kube::kubectl_wait -n "${__KUBEVIRT_NAMESPACE}" \
    -r "${__KUBEVIRT_DEPLOYMENT_OPERATOR}" \
    || return
  
  kube::kustomize_build_apply "${kustomize_dir}/cr" || return
  kube::kubectl_wait -n "${__KUBEVIRT_NAMESPACE}" \
    -r "${__KUBEVIRT_CR_KUBEVIRT}" \
    || return
}

# shellcheck source=../git/submodule.sh
. "${BASH_SOURCE[0]%/*}/../git/submodule.sh"
git::submodule_require "${BASH_SOURCE[0]%/*}/../../vendor/bash-logger/logging.sh"
git::submodule_require "${BASH_SOURCE[0]%/*}/../../vendor/bashkit/local/lib/bashkit/core/logger-utils.sh"

# shellcheck source=../../vendor/bashkit/local/lib/bashkit/core/logger-utils.sh
. "${BASH_SOURCE[0]%/*}/../../vendor/bashkit/local/lib/bashkit/core/logger-utils.sh"

# shellcheck source=../../vendor/bashkit/local/lib/bashkit/kube/kube.sh
. "${BASH_SOURCE[0]%/*}/../../vendor/bashkit/local/lib/bashkit/kube/kube.sh"
