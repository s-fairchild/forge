# hack/lib/kubevirt/kubevirt.sh
#
# shellcheck shell=bash

[[ "${XTRACE:=0}" -eq 1 ]] && set -x

set -o nounset \
  -o errexit \
  -o pipefail \
  -o noclobber \
  -o hashall

declare -r __hack_lib_kubevirt_sourced="true"

###############################
### Configuration Constants ###
###############################

# Version pins live in the referenced kustomization.yaml files' resources: URLs, not here --
# see pkg/operators/kubevirt/{operator,cr}/kustomization.yaml and
# pkg/operators/cdi/{operator,cr}/kustomization.yaml.
declare -r __KUBEVIRT_KUSTOMIZATION_DEFAULT="pkg/operators/kubevirt/overlays/staging"
declare -r __KUBEVIRT_NAMESPACE="kubevirt"

declare -r __CDI_KUSTOMIZATION_DEFAULT="pkg/operators/cdi/overlays/staging"
declare -r __CDI_NAMESPACE="cdi"

declare -r __KUBECTL_WAIT_TIMEOUT_DEFAULT="300s"

# kubevirt_install()
#
# Idempotently applies the pinned KubeVirt operator and CR (kubectl apply is itself
# idempotent) against the current kubeconfig context, and waits for the operator
# Deployment and the KubeVirt CR to become Available. The operator and CR are applied
# (and waited on) as two separate steps because the CR's CRD is only registered once
# the operator is running -- applying both at once races the CRD not existing yet.
# shellcheck disable=SC2120  # takes no arguments; the debug trace's "$*" is boilerplate
kubevirt_install() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  local -r kustomize_dir="${1:-$__KUBEVIRT_KUSTOMIZATION_DEFAULT}"
  local -r kubectl_wait_timeout="${2:-$__KUBECTL_WAIT_TIMEOUT_DEFAULT}"

  info "Applying ${kustomize_dir}"
  if ! kubectl apply -k "$kustomize_dir"; then
    fatal "failed to apply $kustomize_dir"
  fi

  local -r deployment_virt_operator="deployment/virt-operator"
  if ! kubectl wait "$deployment_virt_operator" \
    -n "${__KUBEVIRT_NAMESPACE}" \
    --for=condition=Available \
    --timeout="$kubectl_wait_timeout"; then
    fatal "virt-operator did not become Available within ${kubectl_wait_timeout}"
  fi

  local -r kv_kubevirt="kv/kubevirt"
  if ! kubectl wait "$kv_kubevirt" \
    -n "${__KUBEVIRT_NAMESPACE}" \
    --for=condition=Available \
    --timeout="$kubectl_wait_timeout"; then
    fatal "KubeVirt CR did not become Available within $kubectl_wait_timeout"
  fi
}

# cdi_install()
#
# Idempotently applies the pinned CDI (Containerized Data Importer) operator and CR,
# and waits for both to become Available. CDI provides the DataVolume/DataImportCron
# CRDs used to populate KubeVirt VM disks (e.g. from a registry-sourced image) at the
# block/filesystem level. Split into two applies for the same CRD-ordering reason as
# kubevirt_install().
# shellcheck disable=SC2120  # takes no arguments; the debug trace's "$*" is boilerplate
cdi_install() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  local -r kustomize_dir="${1:-$__CDI_KUSTOMIZATION_DEFAULT}"
  local -r kubectl_wait_timeout="${2:-$__KUBECTL_WAIT_TIMEOUT_DEFAULT}"

  info "Applying ${kustomize_dir}"
  if ! kubectl apply -k "$kustomize_dir"; then
    fatal "failed to apply ${kustomize_dir}"
  fi

  local -r deployment_cdi_operator="deployment/cdi-operator"
  if ! kubectl wait "$deployment_cdi_operator" \
    -n "${__CDI_NAMESPACE}" \
    --for=condition=Available \
    --timeout="$kubectl_wait_timeout"; then
    fatal "cdi-operator did not become Available within ${kubectl_wait_timeout}"
  fi

  local -r cdi_cdi="cdi/cdi"
  # The CDI custom resource is cluster-scoped (no -n).
  if ! kubectl wait "$cdi_cdi" \
    --for=condition=Available \
    --timeout="$kubectl_wait_timeout"; then
    fatal "CDI CR did not become Available within ${kubectl_wait_timeout}"
  fi
}

if [[ "${__bash_logger_adapter_sourced:-}" != "true" ]]; then
  declare __bash_logger_adapter_path="hack/vendor/bash-logger-adapter/adapter.sh"
  [[ -f "${__bash_logger_adapter_path}" ]] || { printf '%s\n' "failed to find file: ${__bash_logger_adapter_path}" >&2; exit 1; }
  # shellcheck source=../../vendor/bash-logger-adapter/adapter.sh
  . "${__bash_logger_adapter_path}"
  unset __bash_logger_adapter_path
fi
