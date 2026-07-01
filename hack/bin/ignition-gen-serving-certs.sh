#!/bin/bash
#
# hack/bin/ignition-gen-serving-certs.sh

# main()
#
# Generates an nginx TLS private key and self-signed certificate, storing both
# as named podman secrets for use by the ignition serving container.
main() {
    # shellcheck disable=SC2128
    debug "${FUNCNAME}() starting"
    local -r deployment="${1?$(fatal "$ERROR_ARG_REQUIRED: \$1")}"
    debug "$(declare -p deployment)"
    shift

    local -r key_name="ssl-key"
    debug "$(declare -p key_name)"
    local -r cert_name="ssl-cert"
    debug "$(declare -p cert_name)"

    _warn_log() {
        local -r n="${1:-}"
        warn "podman secret $n already exists. Refusing to replace $n. Delete $n to recreate."
    }

    if podman_secret_exists "$key_name"; then
        _warn_log "$key_name"
        return
    elif podman_secret_exists "$cert_name"; then
        _warn_log "$cert_name"
        return
    fi

    _fatal_log() {
        local -r n="${1:-}"
        fatal "failed to generate and save podman secret $n"
    }

    secret_labels_extra+=(
        "deployment=$deployment"
        "type=ssl"
        "ssl=key"
    )

    debug "$(declare -p secret_labels_extra)"
    info "Generating ssl private key... saving to podman secret: $key_name"
    openssl_gen_private_key \
        | podman_secret_create_replace_from_stdin "$key_name" secret_labels_extra \
        || _fatal_log "$key_name"

    secret_labels_extra[${#secret_labels_extra[@]}-1]="ssl=cert"
    info "Generating self signed certificate... saving to podman secret: $cert_name"
    podman_secret_showsecret "$key_name" \
        | openssl_gen_self_signed_certificate "$@" \
        | podman_secret_create_replace_from_stdin "$cert_name" secret_labels_extra \
        || _fatal_log "$cert_name"
}

if [ "${__bash_utils_base_config_logging_sourced:-}" != "true" ]; then
    declare -r __bash_utils_base_config_logging="hack/vendor/bash-utils/lib/base-config-logging.sh"
    [ -f "$__bash_utils_base_config_logging" ] || { printf '%s\n' "failed to find file: $__bash_utils_base_config_logging" >&2; exit 1; }
    # shellcheck source=../lib/logging.sh
    . "$__bash_utils_base_config_logging"
fi

if [ "${__hack_lib_gen_ssl_certificates_sourced:-}" != "true" ]; then
    declare -r gen_ssl_certificates="hack/lib/openssl/openssl-gen-certs.sh"
    [ -f "$gen_ssl_certificates" ] || fatal "$ERROR_FILE_NOT_FOUND: $gen_ssl_certificates"
    info "Sourcing $gen_ssl_certificates"
    # shellcheck source=../lib/openssl/openssl-gen-certs.sh
    . "$gen_ssl_certificates"
fi

if [ "${__lib_podman_secret_sourced:-}" != "true" ]; then
    declare -r podman_secrets="hack/lib/podman/podman-secret.sh"
    [ -f "$podman_secrets" ] || fatal "$ERROR_FILE_NOT_FOUND: $podman_secrets"
    # shellcheck source=../lib/podman/podman-secret.sh
    . "$podman_secrets"
fi

main "$@"
