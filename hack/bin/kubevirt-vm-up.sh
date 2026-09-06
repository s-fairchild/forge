#!/bin/bash
# Idempotently apply a namespace, an ignition-payload Secret (sourced from a podman
# secret), and a KubeVirt VirtualMachine manifest to the current kubectl context.

[ "${XTRACE:-0}" -eq 1 ] && set -x

set -o nounset \
    -o errexit \
    -o pipefail \
    -o noclobber \
    -o hashall

usage() {
    cat <<USAGE >&2
Usage: ${0##*/} -f vm_manifest -n namespace_manifest -s ignition_secret [-k k8s_secret_name] [-v] [-q] [-h]

Idempotently applies <namespace_manifest>, then builds a Kubernetes Secret named
<k8s_secret_name> (default: ignition-payload) in that namespace from the raw contents
of the podman secret <ignition_secret> (key: userdata, as consumed by a
cloudInitConfigDrive volume), then applies <vm_manifest>.

Options:
    -f vm_manifest         Path to the KubeVirt VirtualMachine manifest to apply. (required)
    -n namespace_manifest  Path to the Namespace manifest to apply first. (required)
    -s ignition_secret     Podman secret name holding the compiled ignition JSON
                            (e.g. ignition-staging). (required)
    -k k8s_secret_name     Name of the Kubernetes Secret to create/update. (default: ignition-payload)
    -v                     Enable verbose/DEBUG-level logging for this invocation, overriding VERBOSE/DEBUG.
    -q                     Suppress console logging for this invocation, overriding QUIET.
    -h                     Print this help message and exit.
USAGE
}

main() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    local vm_manifest="" namespace_manifest="" ignition_secret="" k8s_secret_name="ignition-payload" opt
    local -i OPTIND=1 cli_verbose=0 cli_quiet=0
    while getopts ':f:n:s:k:vqh' opt; do
        case "$opt" in
            f)
                is_option_arg_dup "$opt" "$vm_manifest"
                vm_manifest="$OPTARG"
                ;;
            n)
                is_option_arg_dup "$opt" "$namespace_manifest"
                namespace_manifest="$OPTARG"
                ;;
            s)
                is_option_arg_dup "$opt" "$ignition_secret"
                ignition_secret="$OPTARG"
                ;;
            k)
                k8s_secret_name="$OPTARG"
                ;;
            v) cli_verbose=1 ;;
            q) cli_quiet=1 ;;
            h) usage; exit 0 ;;
            :) usage; fatal "-${OPTARG} $ERROR_OPTION_REQUIRED" ;;
            ?) usage; fatal "-${OPTARG} $ERROR_OPTION_UNKNOWN" ;;
        esac
    done
    shift $((OPTIND - 1))

    bash_logger_adapter_apply_overrides "$cli_verbose" \
                                        "$cli_quiet" \
                                        "$__bash_logger_adapter_env_log_level"

    [ -n "$vm_manifest" ]        || { usage; fatal "-f $ERROR_OPTION_REQUIRED"; }
    [ -n "$namespace_manifest" ] || { usage; fatal "-n $ERROR_OPTION_REQUIRED"; }
    [ -n "$ignition_secret" ]    || { usage; fatal "-s $ERROR_OPTION_REQUIRED"; }
    [ -f "$vm_manifest" ]        || { usage; fatal "$ERROR_FILE_NOT_FOUND: $vm_manifest"; }
    [ -f "$namespace_manifest" ] || { usage; fatal "$ERROR_FILE_NOT_FOUND: $namespace_manifest"; }
    local -r vm_manifest namespace_manifest ignition_secret k8s_secret_name
    debug "$(declare -p vm_manifest namespace_manifest ignition_secret k8s_secret_name)"

    info "Applying namespace manifest $namespace_manifest"
    if ! kubectl apply -f "$namespace_manifest"; then
      fatal "kubectl apply -f $namespace_manifest failed"
    fi

    local namespace
    if ! namespace="$(yq eval '.metadata.name' "$namespace_manifest")"; then
      fatal "failed to read .metadata.name from $namespace_manifest"
    fi
    local -r namespace
    [ -n "$namespace" ] && [ "$namespace" != "null" ] || fatal "$namespace_manifest has no .metadata.name"

    info "Applying Secret $k8s_secret_name in namespace $namespace from podman secret $ignition_secret"
    # xtrace must be off before the secret is read into the shell, not just before it's
    # used -- it's the trace line's expanded arguments that would leak the value.
    # shellcheck disable=SC2034 # populated via nameref inside with_xtrace_suppressed
    local -i ignition_xtrace_was_on=0
    with_xtrace_suppressed save ignition_xtrace_was_on

    local ignition_userdata
    ignition_userdata="$(podman_secret_showsecret "$ignition_secret" | jq -c)"
    kubectl --namespace="$namespace" \
            create \
            secret \
            generic \
            "$k8s_secret_name" \
            --from-literal="userdata=${ignition_userdata}" \
            --dry-run=client \
            -o yaml \
        | kubectl apply -f - || fatal "failed to apply Secret $k8s_secret_name"
    unset ignition_userdata

    with_xtrace_suppressed restore ignition_xtrace_was_on

    info "Applying VirtualMachine manifest $vm_manifest"
    kubectl apply -f "$vm_manifest" || fatal "kubectl apply -f $vm_manifest failed"
}

if [ "${__bash_logger_adapter_sourced:-}" != "true" ]; then
    declare __bash_logger_adapter_path="hack/vendor/bash-logger-adapter/adapter.sh"
    [ -f "$__bash_logger_adapter_path" ] || { printf '%s\n' "failed to find file: $__bash_logger_adapter_sourced" >&2; exit 1; }
    # shellcheck source=../vendor/bash-logger-adapter/adapter.sh
    . "$__bash_logger_adapter_path"
    unset __bash_logger_adapter_path
fi

if [ "${__vendor_bashkit_local_lib_bashkit_options_operands_utils_sourced:-}" != "true" ]; then
    declare __vendor_bashkit_local_lib_bashkit_options_operands_utils="hack/vendor/bashkit/local/lib/bashkit/options-operands-utils.sh"
    [ -f "$__vendor_bashkit_local_lib_bashkit_options_operands_utils" ] || fatal "${ERROR_FILE_NOT_FOUND}: ${__vendor_bashkit_local_lib_bashkit_options_operands_utils}"
    # shellcheck source=../vendor/bashkit/local/lib/bashkit/options-operands-utils.sh
    . "$__vendor_bashkit_local_lib_bashkit_options_operands_utils"
    unset __vendor_bashkit_local_lib_bashkit_options_operands_utils
fi

if [ "${__hack_lib_yq_sourced:-}" != "true" ]; then
    declare __hack_lib_yq="hack/lib/yq.sh"
    [ -f "$__hack_lib_yq" ] || fatal "$ERROR_FILE_NOT_FOUND: $__hack_lib_yq"
    # shellcheck source=../lib/yq.sh
    . "$__hack_lib_yq"
    unset __hack_lib_yq
fi

if [ "${__lib_podman_secret_sourced:-}" != "true" ]; then
    declare podman_secrets="hack/lib/podman/podman-secret.sh"
    [ -f "$podman_secrets" ] || { printf '%s\n' "failed to find file: $podman_secrets" >&2; exit 1; }
    # shellcheck source=../lib/podman/podman-secret.sh
    . "$podman_secrets"
    unset podman_secrets
fi

main "$@"
