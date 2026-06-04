#!/bin/bash
#
# hack/bin/ignition-serve-gen-certificates.sh

main() {
    # shellcheck disable=SC2128
    info "${FUNCNAME}() starting"

    local -r key_name="nginx-ssl-private-key"
    info "Generating ssl private key... saving to podman secret: $key_name"

    local -r fatal_msg_common="failed to generate and save podman secret"
    openssl_gen_private_key \
    | podman_create_replace_secret "$key_name" \
    || fatal "${fatal_msg_common}: $key_name"

    local -r cert_name="nginx-ssl-certificate"
    info "Generating self signed certificate... saving to podman secret: $cert_name"

    podman_secret_showsecret "$key_name" \
    | openssl_gen_self_signed_certificate \
    | podman_create_replace_secret "$cert_name" \
    || fatal "${fatal_msg_common}: $cert_name"
}

declare fatal_msg_file_not_found="could not find file to source"
declare fatal_msg_source_failed="failed to source file"
if [ "${__lib_opt_bash_utils_logging_sourced:-}" != "true" ]; then
    declare -r shell_utils_logging="hack/lib/opt-bash-utils-logging.sh"
    [ -f "$shell_utils_logging" ] || "$(echo "${fatal_msg_file_not_found}: $shell_utils_logging"; exit 5)"

    echo "Sourcing $shell_utils_logging"
    # shellcheck source=../lib/opt-bash-utils-logging.sh
    . "$shell_utils_logging" || "$(echo "${fatal_msg_source_failed}: $shell_utils_logging"; exit 6)"
fi

if [ "${__hack_lib_gen_ssl_certificates_sourced:-}" != "true" ]; then
    declare -r gen_ssl_certificates="hack/lib/gen-ssl-certificates.sh"
    [ -f "$gen_ssl_certificates" ] || fatal "${fatal_msg_file_not_found}: $gen_ssl_certificates"

    info "Sourcing $gen_ssl_certificates"
    # shellcheck source=../lib/gen-ssl-certificates.sh
    . "$gen_ssl_certificates" || fatal "${fatal_msg_source_failed}: $gen_ssl_certificates"
fi

if [ "${__hack_lib_podman_secrets_create_sourced:-}" != "true" ]; then
    declare -r podman_secrets_create="hack/lib/podman/podman-secret-create.sh"
    [ -f "$podman_secrets_create" ] || fatal "${fatal_msg_file_not_found}: $podman_secrets_create"

    info "Sourcing $podman_secrets_create"
    # shellcheck source=../lib/podman/podman-secret-create.sh
    . "$podman_secrets_create" || fatal "${fatal_msg_source_failed}: $podman_secrets_create"
fi

main "$@"
