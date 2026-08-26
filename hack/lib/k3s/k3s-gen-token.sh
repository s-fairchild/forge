# shellcheck shell=bash

declare -r __hack_lib_k3s_gen_token_sourced="true"

# k3s_gen_token_openssl()
#
# Generates a 64-character lowercase hex token using `openssl rand -hex 32`.
k3s_gen_token_openssl() {
    log_debug "Starting ${FUNCNAME[0]}()"
    openssl rand -hex 32
}

# k3s_gen_token_tr()
#
# Generates a 64-character lowercase hex token using `tr` + `head` as a
# fallback when openssl is unavailable.  head triggers SIGPIPE to tr; the
# resulting non-zero exit is suppressed.
k3s_gen_token_tr() {
    log_debug "Starting ${FUNCNAME[0]}()"
    # head triggers SIGPIPE to tr; suppress the resulting non-zero exit
    tr -dc 'a-f0-9' </dev/urandom | head -c 64 || true
}

# k3s_gen_token_shasum()
#
# Generates a 64-character lowercase hex token using sha256sum as a secondary
# fallback when neither openssl nor tr is available.
k3s_gen_token_shasum() {
    log_debug "Starting ${FUNCNAME[0]}()"
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
    log_debug "Starting ${FUNCNAME[0]}()"

    local -r error_prefix="failed to generate token with"
    if which openssl > /dev/null 2>&1; then
        k3s_gen_token_openssl || log_error "$error_prefix openssl."
    elif which tr > /dev/null 2>&1; then
        log_warn "openssl not found. Falling back to tr."
        k3s_gen_token_tr || log_error "$error_prefix tr."
    else
        log_warn "tr not found. Falling back to shasum."
        k3s_gen_token_shasum || log_error "$error_prefix shasum."
    fi
}

if [ "${__bash_logger_adapter_sourced:-}" != "true" ]; then
    declare __bash_logger_adapter_path="hack/vendor/bash-logger-adapter/adapter.sh"
    [ -f "$__bash_logger_adapter_path" ] || { printf '%s\n' "failed to find file: $__bash_logger_adapter_sourced" >&2; exit 1; }
    # shellcheck source=../../vendor/bash-logger-adapter/adapter.sh
    . "$__bash_logger_adapter_path"
    unset __bash_logger_adapter_path
fi
