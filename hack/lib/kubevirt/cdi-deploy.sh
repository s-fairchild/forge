# shellcheck shell=bash
#
# kubevirt::cdi_deploy: applies the pinned CDI operator and CR and waits for both to
# become Available.

set -euCho pipefail

###############################
### Configuration Constants ###
###############################

# Version pins live in the referenced kustomization.yaml files' resources: URLs, not here --
# see pkg/operators/kubevirt/{operator,cr}/kustomization.yaml and
# pkg/operators/cdi/{operator,cr}/kustomization.yaml.
[[ -v __CDI_KUSTOMIZATION_DEFAULT ]] \
  || readonly __CDI_KUSTOMIZATION_DEFAULT="pkg/operators/cdi"
[[ -v __CDI_NAMESPACE ]] \
  || readonly __CDI_NAMESPACE="cdi"
[[ -v __CDI_DEPLOYMENT_OPERATOR ]] \
  || readonly __CDI_DEPLOYMENT_OPERATOR="deployment/cdi-operator"
[[ -v __CDI_CR_CDI ]] \
  || readonly __CDI_CR_CDI="cdi/cdi"

# kubevirt::cdi_deploy([kustomize_dir])
#
# Idempotently applies the pinned CDI (Containerized Data Importer) operator and CR,
# building each with kustomize, and waits for both to become Available. CDI provides
# the DataVolume/DataImportCron CRDs used to populate KubeVirt VM disks (e.g. from a
# registry-sourced image) at the block/filesystem level. Split into two applies for
# the same CRD-ordering reason as kubevirt::deploy().
#
# Globals:
#   __CDI_KUSTOMIZATION_DEFAULT   Read as the default <kustomize_dir>.
#   __CDI_NAMESPACE               Read as the namespace to wait in.
#   __CDI_DEPLOYMENT_OPERATOR     Read as the operator resource to wait on.
#   __CDI_CR_CDI                  Read as the CR resource to wait on.
# Arguments:
#   $1   Optional. Directory holding the operator/ and cr/ kustomizations.
#        Defaults to pkg/operators/cdi.
# Outputs:
#   Log lines from kube::kustomize_build_apply and kube::kubectl_wait; an error and
#   stack trace if <kustomize_dir> isn't a directory.
# Returns:
#   1 if <kustomize_dir> isn't a directory; otherwise the status of the last wait.
#   The steps have no `|| return`, so an earlier failure stops the function only
#   under errexit.
# shellcheck disable=SC2120  # callers pass no arguments and rely on the default
kubevirt::cdi_deploy() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  local -r kustomize_dir="${1:-${__CDI_KUSTOMIZATION_DEFAULT}}"

  if ! [[ -d "${kustomize_dir}" ]]; then
    core::fail "kustomize dir not found: ${kustomize_dir}" || return
  fi

  kube::kustomize_build_apply "${kustomize_dir}/operator"
  kube::kubectl_wait -n "${__CDI_NAMESPACE}" -r "${__CDI_DEPLOYMENT_OPERATOR}"
  
  kube::kustomize_build_apply "${kustomize_dir}/cr"
  kube::kubectl_wait -n "${__CDI_NAMESPACE}" -r "${__CDI_CR_CDI}"
}

# shellcheck source=../git/submodule.sh
. "${BASH_SOURCE[0]%/*}/../git/submodule.sh"
git::submodule_require "${BASH_SOURCE[0]%/*}/../../vendor/bash-logger/logging.sh"
git::submodule_require "${BASH_SOURCE[0]%/*}/../../vendor/bashkit/local/lib/bashkit/core/logger-utils.sh"

# shellcheck source=../../vendor/bashkit/local/lib/bashkit/core/logger-utils.sh
. "${BASH_SOURCE[0]%/*}/../../vendor/bashkit/local/lib/bashkit/core/logger-utils.sh"

# shellcheck source=../../vendor/bashkit/local/lib/bashkit/kube/kube.sh
. "${BASH_SOURCE[0]%/*}/../../vendor/bashkit/local/lib/bashkit/kube/kube.sh"
