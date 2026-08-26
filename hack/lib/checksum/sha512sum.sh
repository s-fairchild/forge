# shellcheck shell=bash

declare -r __hack_lib_checksum_sha512sum_sourced="true"

sha512sum() {
    # shellcheck disable=SC2068
    command sha512sum $@
}

sha512sum_gen_stdin() {
    debug "Starting ${FUNCNAME[0]}()"

    if [ -t 0 ]; then
        error "$ERROR_STDIN_NULL"
        return 1
    fi

    cat | sha512sum -
}

sha512sum_check_stdin() {
    debug "Starting ${FUNCNAME[0]}()"

    if [ -t 0 ]; then
        error "$ERROR_OPERAND_REQUIRED"
        return 1
    fi

    local -ar sha512sum_check_options=(
        "--check"
        "--strict"
        --warn
    )
    debug "$(declare -p sha512sum_check_options)"

    # shellcheck disable=SC2068
    sha512sum ${sha512sum_check_options[@]} -
}

sha512sum_gen() {
    debug "Starting ${FUNCNAME[0]}()"

    if (( $# )); then
        local -r input="$1"
    elif [ ! -t 0 ]; then
        local -r input="$(cat)"
    else
        error "$ERROR_STDIN_NULL OR $ERROR_OPERAND_REQUIRED"
        return 1
    fi
    
    sha512sum_gen_stdin <<< "$input"
}

sha512sum_check() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    if (( $# )); then
        local -r input="$1"
    elif [ ! -t 0 ]; then
        local -r input="$(cat)"
    else
        error "$ERROR_STDIN_NULL OR $ERROR_OPERAND_REQUIRED"
        return 1
    fi

    sha512sum_check_stdin <<< "$input"
}

if [ "${__bash_logger_adapter_sourced:-}" != "true" ]; then
    declare __bash_logger_adapter_path="hack/vendor/bash-logger-adapter/adapter.sh"
    [ -f "$__bash_logger_adapter_path" ] || { printf '%s\n' "failed to find file: $__bash_logger_adapter_sourced" >&2; exit 1; }
    # shellcheck source=../../vendor/bash-logger-adapter/adapter.sh
    . "$__bash_logger_adapter_path"
    unset __bash_logger_adapter_path
fi
