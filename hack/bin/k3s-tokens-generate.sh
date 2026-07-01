#!/bin/bash

set -o nounset \
    -o errexit \
    -o pipefail \
    -o noclobber \
    -o hashall

[ "${XTRACE:-0}" -eq 1 ] && set -x

# main()
#
# Generates k3s cluster authentication tokens as podman secrets and produces
# a secretsdata.json for the podman file secret driver.
#
# For each token name in k3s_tokens (k3s-token, k3s-agent-token): if the
# podman secret does not already exist, a 64-character hex token is generated
# and stored as a podman secret.  Existing secrets are left unchanged with a
# warning — delete the secret manually before re-running to rotate.
#
# After token generation, a secretsdata.json blob is produced by inspecting
# all generated secrets and written as a podman secret under secretsdata_name.
# This JSON is the format consumed by the podman file secret driver and can be
# deployed directly to /var/lib/containers/storage/secrets/filedriver/ on a
# remote host via ignition (see deploy/butane/overlays/prod/etc-containers-secrets.bu).
#
# args:
#   * 1) secretsdata_name - string; name for the podman secret that will hold
#         the generated secretsdata.json file driver blob.
#
# env:
#   * XTRACE=1 - enable bash xtrace for this script.
main() {
    local -r secretsdata_name="$1"

    local -r error_msg_secret_exists="already exists, Refusing to replace. Delete and re-run to update."

    local -A k3s_tokens=(
        ["k3s-token"]=""
        ["k3s-agent-token"]=""
    )

    local -r error_msg_secret_create="failed to create podman secret"
    # shellcheck disable=SC2068
    for s in ${!k3s_tokens[@]}; do
        if ! podman_secret_exists "$s"; then
            info "Generating token for: $s"

            k3s_tokens["$s"]="$(generate_token)" || fatal "token generation failed."
            podman_secret_create_replace_from_stdin "$s" <<< "${k3s_tokens["$s"]}" || fatal "$error_msg_secret_create: $s"

            # secret is stored in podman secret driver format, remove from memory.
            k3s_tokens[$s]=""
        else
            warn "podman secret $s $error_msg_secret_exists"
        fi
    done

    if ! podman_secret_exists "$secretsdata_name"; then
        info "Generating podman secret file driver secretsdata.json"
        podman_secret_create_replace_from_stdin "$secretsdata_name" \
            <<< "$(podman_secret_gen_file_secretsdata <<< "${!k3s_tokens[*]}")" \
            || fatal "$error_msg_secret_create: $secretsdata_name"
    else
        warn "podman secret $secretsdata_name $error_msg_secret_exists"
    fi
}

if [ "${__bash_utils_base_config_logging_sourced:-}" != "true" ]; then
    declare -r __bash_utils_base_config_logging="hack/vendor/bash-utils/lib/base-config-logging.sh"
    [ -f "$__bash_utils_base_config_logging" ] || { printf '%s\n' "failed to find file: $__bash_utils_base_config_logging" >&2; exit 1; }
    # shellcheck source=../vendor/bash-utils/lib/base-config-logging.sh
    . "$__bash_utils_base_config_logging"
fi

if [ "${__hack_lib_k3s_gen_token_sourced:-}" != "true" ]; then
    declare -r __hack_lib_k3s_gen_token="hack/lib/k3s/k3s-gen-token.sh"
    [ -f "$__hack_lib_k3s_gen_token" ] || fatal "$ERROR_FILE_NOT_FOUND: $__hack_lib_k3s_gen_token"
    # shellcheck source=../lib/k3s/k3s-gen-token.sh
    . "$__hack_lib_k3s_gen_token"
fi

if [ "${__lib_podman_secret_sourced:-}" != "true" ]; then
    declare -r podman_secrets="hack/lib/podman/podman-secret.sh"
    [ -f "$podman_secrets" ] || fatal "$ERROR_FILE_NOT_FOUND: $podman_secrets"
    # shellcheck source=../lib/podman/podman-secret.sh
    . "$podman_secrets"
fi

main "$@"
