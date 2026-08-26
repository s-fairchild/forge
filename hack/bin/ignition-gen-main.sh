#!/bin/bash
# Recursively generate all ignition files

[ "${XTRACE:-0}" -eq 1 ] && set -x

set -o nounset \
    -o errexit \
    -o pipefail \
    -o noclobber \
    -o hashall

usage() {
    cat <<USAGE >&2
Usage: ${0##*/} -f butane_file -p ignition_secret_postfix [-s secret_name]... [-l label]... [-v] [-q] [-h]

Recursively compile a root butane config, merging its inline references,
and store the resulting ignition JSON as a podman secret named ignition-<ignition_secret_postfix>.

Options:
    -f butane_file   Path to the root butane config to compile and merge. (required)
    -p ignition_secret_postfix Suffix appended to "ignition-" to form the podman secret name
                     (e.g. -p prod stores the result as "ignition-prod"). (required)
    -s secret_name   Podman secret name to mount into the butane container as a file under
                     files/secrets/<secret_name>. May be specified multiple times.
    -l label         Additional "key=value" label to attach to secrets created
                     during generation. May be specified multiple times.
    -v               Enable verbose/log_debug logging for this invocation, overriding VERBOSE/DEBUG.
    -q               Suppress console logging for this invocation, overriding QUIET.
    -h               Print this help message and exit.
USAGE
}

main() {
    log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    local -a labels=() secret_mounts=()
    local ignition_secret_postfix="" butane_file="" opt
    local -i OPTIND=1 cli_verbose=0 cli_quiet=0
    while getopts ':s:p:l:f:vqh' opt; do
        case "$opt" in
            p)
                # [ -z "${ignition_secret_postfix:-}" ] || { usage; log_fatal "-${opt} ${ERROR_OPTION_ARG_DUP}"; }
                is_option_arg_dup "$opt" "$ignition_secret_postfix"
                ignition_secret_postfix="${OPTARG}"
                local -r ignition_secret_postfix
                ;;
            s)
                # -s is inserted via ignition_gen()
                secret_mounts+=("${OPTARG}")
                ;;
            l)
                # -l is inserted as an index before $OPTARG to preserve spacing when passed to podman_secret_create_replace_from_stdin()
                labels+=("-${opt}" "${OPTARG}")
                ;;
            f)
                is_option_arg_dup "$opt" "$butane_file"
                butane_file="${OPTARG}"
                local -r butane_file
                ;;
            v)
                cli_verbose=1
                ;;
            q)
                cli_quiet=1
                ;;
            h)
                usage
                exit 0
                ;;
            :)
                usage
                log_fatal "-${OPTARG} $ERROR_OPTION_REQUIRED"
                ;;
            ?)
                usage
                log_fatal "-${OPTARG} $ERROR_OPTION_UNKNOWN"
                ;;
        esac
    done
    shift $((OPTIND - 1))
    # CLI flags take precedence over VERBOSE/QUIET env vars for this invocation (see
    # hack/vendor/bash-logger-adapter/adapter.sh for the general CLI > env > default precedence rule).
    bash_logger_adapter_apply_overrides "$cli_verbose" "$cli_quiet"
    [ -z "${butane_file:-}" ] && { usage; log_fatal "-f $ERROR_OPTION_REQUIRED"; }
    [ -z "${ignition_secret_postfix:-}" ] && { usage; log_fatal "-p $ERROR_OPTION_REQUIRED"; }
    [ -f "${butane_file}" ] || { usage; log_fatal "${ERROR_FILE_NOT_FOUND}: ${butane_file}"; }
    log_debug "$(declare -p ignition_secret_postfix labels butane_file)"

    # shellcheck disable=SC2034
    local ignition_main
    ignition_gen_config_merge_inlines "$butane_file" \
                                       ignition_main \
                                       secret_mounts \
                                       || log_fatal "ignition_gen_config_merge_inlines failed."

    labels+=("-l" "format=ignition")
    # shellcheck disable=SC2068
    podman_secret_create_replace_from_stdin ${labels[@]} \
                                            "ignition-${ignition_secret_postfix}" \
                                            <<< "$ignition_main" \
                                            || log_fatal "podman_secret_create_replace_from_stdin failed."
}

if [ "${__bash_logger_adapter_sourced:-}" != "true" ]; then
    declare __bash_logger_adapter_path="hack/vendor/bash-logger-adapter/adapter.sh"
    [ -f "$__bash_logger_adapter_path" ] || { printf '%s\n' "failed to find file: $__bash_logger_adapter_sourced" >&2; exit 1; }
    # shellcheck source=../vendor/bash-logger-adapter/adapter.sh
    . "$__bash_logger_adapter_path"
    unset __bash_logger_adapter_path
fi

if [ "${__vendor_bashkit_local_lib_bashkit_options_operands_utils_sourced:-}" != "true" ]; then
    declare __vendor_bashkit_local_lib_bashkit_options_operands_utils="hack/vendor/bashkit/local/lib/bashkit/options-operands-utils.sh"
    [ -f "$__vendor_bashkit_local_lib_bashkit_options_operands_utils" ] || log "$LOG_LEVEL_FATAL"
    # shellcheck source=../vendor/bashkit/local/lib/bashkit/options-operands-utils.sh
    . "$__vendor_bashkit_local_lib_bashkit_options_operands_utils"
    unset __vendor_bashkit_local_lib_bashkit_options_operands_utils
fi

if [ "${__lib_podman_secret_sourced:-}" != "true" ]; then
    declare podman_secrets="hack/lib/podman/podman-secret.sh"
    [ -f "$podman_secrets" ] || { printf '%s\n' "failed to find file: $podman_secrets" >&2; exit 1; }
    # shellcheck source=../lib/podman/podman-secret.sh
    . "$podman_secrets"
    unset podman_secrets
fi

if [ "${__ignition_sourced:-}" != "true" ]; then
    declare ignition_lib="hack/lib/ignition/ignition.sh"
    [ -f "$ignition_lib" ] || log_fatal "$ERROR_FILE_NOT_FOUND: $ignition_lib"
    # shellcheck source=../lib/ignition/ignition.sh
    . "$ignition_lib"
    unset ignition_lib
fi

main "$@"
