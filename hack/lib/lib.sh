# hack/lib/lib.sh
#
# shellcheck shell=bash

declare -r __hack_lib_lib_sourced="true"

# append_array_with_text()
#
append_array_with_text() {
    # shellcheck disable=SC2128
    local -r log_prefix="$FUNCNAME()"
    local -n a="${1?$(fatal "$log_prefix: \$1 a $ERROR_ARG_NOT_PROVIDED")}"
    local -n a_extra="${2?$(fatal "$log_prefix: \$2 a_extra $ERROR_ARG_NOT_PROVIDED")}"
    local -r p="${3:-}"

    [ -v a ] || debug "$log_prefix a=$1 array contains no elements. Is this expected?"
    [ -v a_extra ] || fatal "$log_prefix \$2 a_extra=$2 array must contain elements."
    [ -n "$p" ] || warn "$log_prefix p=\"$p\" No text will be appended."

    local -ir a_len="${#a[@]}"
    local -ir a_extra_len="${#a_extra[@]}"

    debug "$log_prefix Before append: len(a)=$a_len a=\"${a[*]}\""
    debug "$log_prefix appending: len(a_extra)=$a_extra_len a_extra=\"${a_extra[*]}\""
    debug "$log_prefix prefix text: p=\"$p\""

    mapfile -O "$a_len" \
            a \
            < <(printf -- "$p%s\n" "${a_extra[@]}")

    local -r a_len_final="${#a[@]}"

    (( a_len + a_extra_len == a_len_final )) || fatal "$log_prefix len(a)=$a_len + len(a_extra)=$a_extra_len != len(a_len_final)=$a_len_final"

    debug "$log_prefix After append: len(a)=$a_len_final a=${a[*]}"
}

if [ "${__lib_opt_bash_utils_logging_sourced:-}" != "true" ]; then
    declare -r __lib_opt_bash_utils_logging="hack/lib/opt-bash-utils-logging.sh"
    [ -f "$__lib_opt_bash_utils_logging" ] || "$(echo "$ERROR_FILE_NOT_FOUND: $__lib_opt_bash_utils_logging"; exit 1)"

    # shellcheck source=opt-bash-utils-logging.sh
    . "$__lib_opt_bash_utils_logging" || "$(echo "failed to source file: $__lib_opt_bash_utils_logging"; exit 1)"
fi
