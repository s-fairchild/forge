#!/bin/bash
#
# hack/bin/ignition-gen-serving-certs.sh

_warn_log() {
    local -r n="${1?$(log_fatal "\$1 ${ERROR_OPERAND_REQUIRED}")}"
    log_warn "podman secret $n already exists. Refusing to replace $n. Delete $n to recreate."
}

# main()
#
# Generates an nginx TLS private key and self-signed certificate, storing both
# as named podman secrets for use by the ignition serving container.
main() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    local -r environment="${1?$(log_fatal "\$1 ${ERROR_OPERAND_REQUIRED}")}"
    shift

    local -r key_name="ssl-key-${environment}" cert_name="ssl-cert-${environment}"
    log_debug "$(declare -p environment key_name cert_name)"

    if podman_secret_exists "$key_name"; then
        _warn_log "$key_name"
        return
    elif podman_secret_exists "$cert_name"; then
        _warn_log "$cert_name"
        return
    fi

    local -r fatal_msg_prefix="failed to generate and save podman secret"
    local -a labels_common=(
            "-l"
            "environment=${environment}"
            "-l"
            "type=ssl"
    )

    log_info "Generating ssl private key... saving to podman secret: $key_name"
    # shellcheck disable=SC2068
    openssl_gen_private_key \
    | podman_secret_create_replace_from_stdin \
        ${labels_common[@]} \
        -l "ssl=key" \
        "$key_name" \
        || log_fatal "${fatal_msg_prefix}: $key_name"

    log_info "Generating self signed certificate... saving to podman secret: $cert_name"
    # shellcheck disable=SC2068
    podman_secret_showsecret "$key_name" \
        | openssl_gen_self_signed_certificate "$@" \
        | podman_secret_create_replace_from_stdin \
            ${labels_common[@]} \
            -l "ssl=cert" \
            "$cert_name" \
        || log_fatal "${fatal_msg_prefix}: $cert_name"
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
    [ -f "$__vendor_bashkit_local_lib_bashkit_options_operands_utils" ] || log "$LOG_LEVEL_FATAL"
    # shellcheck source=../vendor/bashkit/local/lib/bashkit/options-operands-utils.sh
    . "$__vendor_bashkit_local_lib_bashkit_options_operands_utils"
    unset __vendor_bashkit_local_lib_bashkit_options_operands_utils
fi

if [ "${__hack_lib_openssl_gen_certs_sourced:-}" != "true" ]; then
    declare gen_ssl_certificates="hack/lib/openssl/openssl-gen-certs.sh"
    [ -f "$gen_ssl_certificates" ] || log_fatal "$ERROR_FILE_NOT_FOUND: $gen_ssl_certificates"
    log_info "Sourcing $gen_ssl_certificates"
    # shellcheck source=../lib/openssl/openssl-gen-certs.sh
    . "$gen_ssl_certificates"
    unset gen_ssl_certificates
fi

if [ "${__lib_podman_secret_sourced:-}" != "true" ]; then
    declare podman_secrets="hack/lib/podman/podman-secret.sh"
    [ -f "$podman_secrets" ] || log_fatal "$ERROR_FILE_NOT_FOUND: $podman_secrets"
    # shellcheck source=../lib/podman/podman-secret.sh
    . "$podman_secrets"
    unset podman_secrets
fi

main "$@"
