# shellcheck shell=bash

declare -r __hack_lib_k3s_gen_token_sourced="true"

# k3s_gen_token_openssl()
#
# Generates a 64-character lowercase hex token using `openssl rand -hex 32`.
k3s_gen_token_openssl() {
    debug "Starting ${FUNCNAME[0]}()"
    openssl rand -hex 32
}

# k3s_gen_token_tr()
#
# Generates a 64-character lowercase hex token using `tr` + `head` as a
# fallback when openssl is unavailable.  head triggers SIGPIPE to tr; the
# resulting non-zero exit is suppressed.
k3s_gen_token_tr() {
    debug "Starting ${FUNCNAME[0]}()"
    # head triggers SIGPIPE to tr; suppress the resulting non-zero exit
    tr -dc 'a-f0-9' </dev/urandom | head -c 64 || true
}

# k3s_gen_token_shasum()
#
# Generates a 64-character lowercase hex token using sha256sum as a secondary
# fallback when neither openssl nor tr is available.
k3s_gen_token_shasum() {
    debug "Starting ${FUNCNAME[0]}()"
    # sha256sum produces 64 hex chars with no trailing spaces
    head -c 32 /dev/urandom | sha256sum | cut -d ' ' -f 1
}

# k3s_gen_token()
#
# Generates a 64-character lowercase hex token for use as a k3s cluster token.
# Tries openssl first, falls back to tr, then sha256sum.
#
# Reference: https://github.com/alexellis/k3sup#create-a-multi-master-ha-setup-with-external-sql
k3s_gen_token() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    local -r error_prefix="failed to generate token with"

    if which openssl > /dev/null 2>&1; then
        k3s_gen_token_openssl || error "$error_prefix openssl."
    elif which tr > /dev/null 2>&1; then
        warn "openssl not found. Falling back to tr."
        k3s_gen_token_tr || error "$error_prefix tr."
    else
        warn "tr not found. Falling back to shasum."
        k3s_gen_token_shasum || error "$error_prefix shasum."
    fi
}

if [ "${__bash_utils_base_config_logging_sourced:-}" != "true" ]; then
    declare __bash_utils_base_config_logging="hack/vendor/bash-utils/lib/base-config-logging.sh"
    [ -f "$__bash_utils_base_config_logging" ] || { printf '%s\n' "failed to find file: $__bash_utils_base_config_logging" >&2; exit 1; }
    # shellcheck source=../../vendor/bash-utils/lib/base-config-logging.sh
    . "$__bash_utils_base_config_logging"
    unset __bash_utils_base_config_logging
fi

if [ "${__hack_env_vendor_sourced:-}" != "true" ]; then
    declare __hack_env_vendor="hack/env/vendor"
    [ -f "$__hack_env_vendor" ] || fatal "$ERROR_FILE_NOT_FOUND: $__hack_env_vendor"
    # shellcheck source=../../env/vendor.env
    . "$__hack_env_vendor"
    unset __hack_env_vendor
fi
