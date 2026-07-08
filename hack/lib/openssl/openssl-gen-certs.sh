# hack/lib/openssl/openssl-gen-certs.sh
#
# shellcheck shell=bash

declare -r __lib_gen_ssl_certs_sourced="true"

# openssl_gen_private_key()
#
# Generates an ECC private key with openssl and saves it as a podman secret.
# Outputs the podman secret ID.
openssl_gen_private_key() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    openssl ecparam \
        -name prime256v1 \
        -genkey
}

usage_openssl_gen_self_signed_certificate() {
    cat <<USAGE >&2
Usage: openssl_gen_self_signed_certificate [-d days] [-s subject] [-a san_value]... [-h] < private_key

Generates a self-signed certificate for the ECC private key read from stdin.

Options:
    -d days      Certificate expiration, in days. (default: 1825)
    -s subject   Certificate subject string.
                 (default: "/C=US/ST=New York/L=New York City/O=Local Ignition Server/CN=ignition.local")
    -a san_value Subject Alternative Name value to append (e.g. "DNS:example.local").
                 May be specified multiple times.
                 (default SAN values: "DNS:ignition.local", "DNS:*.ignition.local", "IP:127.0.0.1")
    -h           Print this usage message and exit.
USAGE
}

# openssl_gen_self_signed_certificate()
#
openssl_gen_self_signed_certificate() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    local -r input="$(cat)"
    [ -z "$input" ] && fatal "$__fatal_msg_stdin_null"

    local -i days=1825
    local subj="/C=US/ST=New York/L=New York City/O=Local Ignition Server/CN=ignition.local"
    local -a san_values=("DNS:ignition.local" "DNS:*.ignition.local" "IP:127.0.0.1")
    while getopts ':d:s:a:h' opt; do
        case "$opt" in
            h) usage_openssl_gen_self_signed_certificate; return 0 ;;
            d)
                debug "Updating Expiration Days"
                days=$OPTARG
                ;;
            s)
                debug "Updating subject"
                subj="$OPTARG"
                debug "$(declare -p subj)"
                ;;
            a)
                debug "Appending SAN value"
                san_values+=("$OPTARG")
                debug "$(declare -p san_values)"
                ;;
            :)
                usage_openssl_gen_self_signed_certificate
                error "$ERROR_ARG_REQUIRED: -${OPTARG} requires an argument"
                return 1
                ;;
            ?)
                usage_openssl_gen_self_signed_certificate
                error "$ERROR_OPTION_UNKNOWN: -${OPTARG}"
                return 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    local -r addext="subjectAltName=$(IFS=','; printf '%s' "${san_values[*]}")"

    openssl req \
        -x509 \
        -nodes \
        -key /dev/stdin \
        -days $days \
        -subj "$subj" \
        -addext "$addext" \
        -out /dev/stdout \
        <<< "$input"
}

if [ "${__bash_utils_base_config_logging_sourced:-}" != "true" ]; then
    declare -r __bash_utils_base_config_logging="hack/vendor/bash-utils/lib/base-config-logging.sh"
    [ -f "$__bash_utils_base_config_logging" ] || { printf '%s\n' "failed to find file: $__bash_utils_base_config_logging" >&2; exit 5; }
    # shellcheck source=../../vendor/bash-utils/lib/base-config-logging.sh
    . "$__bash_utils_base_config_logging"
fi

declare -r __fatal_msg_stdin_null="stdin input cannot be null."
