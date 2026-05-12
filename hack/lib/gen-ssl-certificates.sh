# hack/lib/gen-ssl-certificates.sh
#
# shellcheck shell=bash

declare -r __hack_lib_gen_ssl_certificates_sourced="true"

# openssl_gen_private_key()
#
# Generates an ECC private key with openssl and saves it as a podman secret.
# Outputs the podman secret ID.
openssl_gen_private_key() {
    openssl ecparam \
            -name prime256v1 \
            -genkey
}

# openssl_gen_self_signed_certificate()
#
openssl_gen_self_signed_certificate() {
    local -r input="$(cat)"
    [ -z "$input" ] && fatal "$__fatal_msg_stdin_null"

    openssl req -x509 -nodes \
            -key /dev/stdin \
            -days 1825 \
            -subj "/C=US/ST=New York/L=New York City/O=Local Ignition Server/CN=ignition.local" \
            -addext "subjectAltName = DNS:ignition.local, DNS:*.ignition.local, IP:127.0.0.1" \
            -out /dev/stdout \
            <<< "$input"
}

declare __err_file_not_found="could not find file to source"
if [ "${__lib_opt_bash_utils_logging_sourced:-}" != "true" ]; then
    declare -r shell_utils_logging="hack/lib/opt-bash-utils-logging.sh"

    [ -f "$shell_utils_logging" ] || "$(echo "${__err_file_not_found}: $shell_utils_logging"; exit 5)"
    # shellcheck source=opt-bash-utils-logging.sh
    . "$shell_utils_logging"
fi

declare -r __fatal_msg_stdin_null="stdin input cannot be null."
