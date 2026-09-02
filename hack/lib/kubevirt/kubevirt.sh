# hack/lib/kubevirt/kubevirt.sh
#
# shellcheck shell=bash

[ "${XTRACE:-0}" -eq 1 ] && set -x

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
declare -r __KUBEVIRT_OPERATOR_KUSTOMIZATION="pkg/operators/kubevirt/operator"
declare -r __KUBEVIRT_CR_KUSTOMIZATION="pkg/operators/kubevirt/cr"
declare -r __KUBEVIRT_NAMESPACE="kubevirt"

declare -r __CDI_OPERATOR_KUSTOMIZATION="pkg/operators/cdi/operator"
declare -r __CDI_CR_KUSTOMIZATION="pkg/operators/cdi/cr"
declare -r __CDI_NAMESPACE="cdi"

declare -r __KUBECTL_WAIT_TIMEOUT="300s"

# kubevirt_install()
#
# Idempotently applies the pinned KubeVirt operator and CR (kubectl apply is itself
# idempotent) against the current kubeconfig context, and waits for the operator
# Deployment and the KubeVirt CR to become Available. The operator and CR are applied
# (and waited on) as two separate steps because the CR's CRD is only registered once
# the operator is running -- applying both at once races the CRD not existing yet.
# shellcheck disable=SC2120 # takes no arguments; the debug trace's "$*" is boilerplate
kubevirt_install() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    info "Applying $__KUBEVIRT_OPERATOR_KUSTOMIZATION"
    kubectl apply -k "$__KUBEVIRT_OPERATOR_KUSTOMIZATION" || fatal "failed to apply $__KUBEVIRT_OPERATOR_KUSTOMIZATION"
    kubectl wait deployment/virt-operator \
                 -n "$__KUBEVIRT_NAMESPACE" \
                 --for=condition=Available \
                 --timeout="$__KUBECTL_WAIT_TIMEOUT" \
        || fatal "virt-operator did not become Available within ${__KUBECTL_WAIT_TIMEOUT}"

    info "Applying $__KUBEVIRT_CR_KUSTOMIZATION"
    kubectl apply -k "$__KUBEVIRT_CR_KUSTOMIZATION" || fatal "failed to apply $__KUBEVIRT_CR_KUSTOMIZATION"
    kubectl wait kv/kubevirt \
                 -n "$__KUBEVIRT_NAMESPACE" \
                 --for=condition=Available \
                 --timeout="$__KUBECTL_WAIT_TIMEOUT" \
        || fatal "KubeVirt CR did not become Available within ${__KUBECTL_WAIT_TIMEOUT}"
}

# cdi_install()
#
# Idempotently applies the pinned CDI (Containerized Data Importer) operator and CR,
# and waits for both to become Available. CDI provides the DataVolume/DataImportCron
# CRDs used to populate KubeVirt VM disks (e.g. from a registry-sourced image) at the
# block/filesystem level. Split into two applies for the same CRD-ordering reason as
# kubevirt_install().
# shellcheck disable=SC2120 # takes no arguments; the debug trace's "$*" is boilerplate
cdi_install() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    info "Applying $__CDI_OPERATOR_KUSTOMIZATION"
    kubectl apply -k "$__CDI_OPERATOR_KUSTOMIZATION" || fatal "failed to apply $__CDI_OPERATOR_KUSTOMIZATION"
    kubectl wait deployment/cdi-operator \
                 -n "$__CDI_NAMESPACE" \
                 --for=condition=Available \
                 --timeout="$__KUBECTL_WAIT_TIMEOUT" \
        || fatal "cdi-operator did not become Available within ${__KUBECTL_WAIT_TIMEOUT}"

    info "Applying $__CDI_CR_KUSTOMIZATION"
    kubectl apply -k "$__CDI_CR_KUSTOMIZATION" || fatal "failed to apply $__CDI_CR_KUSTOMIZATION"
    # The CDI custom resource is cluster-scoped (no -n).
    kubectl wait cdi/cdi \
                 --for=condition=Available \
                 --timeout="$__KUBECTL_WAIT_TIMEOUT" \
        || fatal "CDI CR did not become Available within ${__KUBECTL_WAIT_TIMEOUT}"
}

if [ "${__bash_logger_adapter_sourced:-}" != "true" ]; then
    declare __bash_logger_adapter_path="hack/vendor/bash-logger-adapter/adapter.sh"
    [ -f "$__bash_logger_adapter_path" ] || { printf '%s\n' "failed to find file: $__bash_logger_adapter_sourced" >&2; exit 1; }
    # shellcheck source=../../vendor/bash-logger-adapter/adapter.sh
    . "$__bash_logger_adapter_path"
    unset __bash_logger_adapter_path
fi
