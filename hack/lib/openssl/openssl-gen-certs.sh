# hack/lib/openssl/openssl-gen-certs.sh
#
# shellcheck shell=bash

declare -r __lib_gen_ssl_certs_sourced="true"

# openssl_gen_private_key()
#
# Generates an ECC private key with openssl and saves it as a podman secret.
# Outputs the podman secret ID.
openssl_gen_private_key() {
    debug "Starting ${FUNCNAME[0]}()"
    openssl ecparam \
        -name prime256v1 \
        -genkey
}

# openssl_gen_self_signed_certificate()
#
openssl_gen_self_signed_certificate() {
    debug "Starting ${FUNCNAME[0]}()"
    local -r input="$(cat)"
    [ -z "$input" ] && fatal "$__fatal_msg_stdin_null"

    local -i days=1825
    local subj="/C=US/ST=New York/L=New York City/O=Local Ignition Server/CN=ignition.local"
    local -a san_values=("DNS:ignition.local" "DNS:*.ignition.local" "IP:127.0.0.1")
    while getopts ':d:s:a:' opt; do
        case "$opt" in
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
                error "$ERROR_ARG_REQUIRED: -${OPTARG} requires an argument"
                return 1
                ;;
            ?)
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
