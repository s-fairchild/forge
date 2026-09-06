# hack/lib/openssl/openssl-gen-certs.sh
#
# shellcheck shell=bash

declare -r __hack_lib_openssl_gen_certs_sourced="true"

# openssl_gen_private_key()
#
# Generates an ECC private key with openssl.
#
# Outputs:
#   The generated private key (PEM) on stdout.
openssl_gen_private_key() {
  debug "Starting ${FUNCNAME[0]}()"

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
# Generates a self-signed certificate for the ECC private key read from stdin.
#
# Arguments:
#   -d days      Certificate expiration, in days. (default: 1825)
#   -s subject   Certificate subject string.
#   -a san_value Subject Alternative Name value to append. Repeatable.
#   -h           Print usage and return 0.
# Outputs:
#   The generated certificate (PEM) on stdout.
# Returns:
#   1 if stdin is empty or option-parsing fails.
openssl_gen_self_signed_certificate() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  local -r input="$(cat)"
  [[ -z "${input}" ]] && fatal "${ERROR_STDIN_NULL}"

  local -i days=1825
  local subj="/C=US/ST=New York/L=New York City/O=Local Ignition Server/CN=ignition.local"
  local -a san_values=("DNS:ignition.local" "DNS:*.ignition.local" "IP:127.0.0.1")
  local opt
  while getopts ':d:s:a:h' opt; do
    case "${opt}" in
      h) usage_openssl_gen_self_signed_certificate; return 0 ;;
      d)
        debug "Updating Expiration Days"
        days="${OPTARG}"
        ;;
      s)
        subj="${OPTARG}"
        log_sensitive "$(declare -p subj)"
        ;;
      a)
        san_values+=("${OPTARG}")
        log_sensitive "$(declare -p san_values)"
        ;;
      :)
        usage_openssl_gen_self_signed_certificate
        error "-${OPTARG} ${ERROR_OPTION_ARG_REQUIRED}"
        return 1
        ;;
      ?)
        usage_openssl_gen_self_signed_certificate
        error "-${OPTARG} ${ERROR_OPTION_UNKNOWN}"
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
    -days "${days}" \
    -subj "${subj}" \
    -addext "${addext}" \
    -out /dev/stdout \
    <<< "${input}"
}

if [[ "${__bash_logger_adapter_sourced:-}" != "true" ]]; then
  declare __bash_logger_adapter_path="hack/vendor/bash-logger-adapter/adapter.sh"
  [[ -f "${__bash_logger_adapter_path}" ]] || { printf '%s\n' "failed to find file: ${__bash_logger_adapter_path}" >&2; exit 1; }
  # shellcheck source=../../vendor/bash-logger-adapter/adapter.sh
  . "${__bash_logger_adapter_path}"
  unset __bash_logger_adapter_path
fi

if [[ "${__vendor_bashkit_local_lib_bashkit_options_operands_utils_sourced:-}" != "true" ]]; then
  declare __vendor_bashkit_local_lib_bashkit_options_operands_utils="hack/vendor/bashkit/local/lib/bashkit/options-operands-utils.sh"
  [[ -f "${__vendor_bashkit_local_lib_bashkit_options_operands_utils}" ]] || fatal "${ERROR_FILE_NOT_FOUND}: ${__vendor_bashkit_local_lib_bashkit_options_operands_utils}"
  # shellcheck source=../../vendor/bashkit/local/lib/bashkit/options-operands-utils.sh
  . "${__vendor_bashkit_local_lib_bashkit_options_operands_utils}"
  unset __vendor_bashkit_local_lib_bashkit_options_operands_utils
fi
