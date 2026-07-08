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
    local -r environment="${1?$(fatal "$ERROR_ARG_REQUIRED: \$1")}"
    debug "$(declare -p environment)"
    shift

    local -r key_name="ssl-key-${environment}" cert_name="ssl-cert-${environment}"
    debug "$(declare -p key_name cert_name)"

    _warn_log() {
        local -r n="${1?$(fatal "$ERROR_ARG_REQUIRED")}"
        warn "podman secret $n already exists. Refusing to replace $n. Delete $n to recreate."
    }

    if podman_secret_exists "$key_name"; then
        _warn_log "$key_name"
        return
    elif podman_secret_exists "$cert_name"; then
        _warn_log "$cert_name"
        return
    fi

    _fatal_log() { fatal "failed to generate and save podman secret ${1:-}"; }

    info "Generating ssl private key... saving to podman secret: $key_name"
    openssl_gen_private_key \
        | podman_secret_create_replace_from_stdin \
            -l "environment=$environment" \
            -l "type=ssl" \
            -l "ssl=key" \
            "$key_name" \
        || _fatal_log "$key_name"

    info "Generating self signed certificate... saving to podman secret: $cert_name"
    podman_secret_showsecret "$key_name" \
        | openssl_gen_self_signed_certificate "$@" \
        | podman_secret_create_replace_from_stdin \
            -l "environment=$environment" \
            -l "type=ssl" \
            -l "ssl=cert" \
            "$cert_name" \
        || _fatal_log "$cert_name"
}

if [ "${__hack_env_vendor_sourced:-}" != "true" ]; then
    declare __hack_env_vendor="hack/env/vendor.env"
    [ -f "$__hack_env_vendor" ] || { printf '%s\n' "failed to find file: $__hack_env_vendor" >&2; exit 1; }
    # shellcheck source=../env/vendor.env
    . "$__hack_env_vendor"
    unset __hack_env_vendor
fi

if [ "${__hack_lib_gen_ssl_certificates_sourced:-}" != "true" ]; then
    declare gen_ssl_certificates="hack/lib/openssl/openssl-gen-certs.sh"
    [ -f "$gen_ssl_certificates" ] || fatal "$ERROR_FILE_NOT_FOUND: $gen_ssl_certificates"
    info "Sourcing $gen_ssl_certificates"
    # shellcheck source=../lib/openssl/openssl-gen-certs.sh
    . "$gen_ssl_certificates"
    unset gen_ssl_certificates
fi

if [ "${__lib_podman_secret_sourced:-}" != "true" ]; then
    declare podman_secrets="hack/lib/podman/podman-secret.sh"
    [ -f "$podman_secrets" ] || fatal "$ERROR_FILE_NOT_FOUND: $podman_secrets"
    # shellcheck source=../lib/podman/podman-secret.sh
    . "$podman_secrets"
    unset podman_secrets
fi

main "$@"
