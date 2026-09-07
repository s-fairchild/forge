#!/bin/bash
# Recursively generate all ignition files

[[ "${XTRACE:-0}" -eq 1 ]] && set -x

set -o nounset \
  -o errexit \
  -o pipefail \
  -o noclobber \
  -o hashall

usage() {
  cat <<USAGE >&2
Usage: ${0##*/} -f butane_file -p ignition_secret_postfix [-s secret_name]...
                 [-l label]... [-v] [-q] [-h]

Recursively compile a root butane config, merging its inline references, and
store the resulting ignition JSON as a podman secret named
ignition-<ignition_secret_postfix>.

Options:
  -f butane_file             Path to the root butane config to compile and
                             merge. (required)
  -p ignition_secret_postfix Suffix appended to "ignition-" to form the
                             podman secret name (e.g. -p prod stores the
                             result as "ignition-prod"). (required)
  -s secret_name             Podman secret name to mount into the butane
                             container as a file under
                             files/secrets/<secret_name>. May be specified
                             multiple times.
  -l label                   Additional "key=value" label to attach to
                             secrets created during generation. May be
                             specified multiple times.
  -v                         Enable verbose/DEBUG-level logging for this
                             invocation, overriding VERBOSE/DEBUG.
  -q                         Suppress console logging for this invocation,
                             overriding QUIET.
  -h                         Print this help message and exit.
USAGE
}

# main()
#
# Entry point: parses CLI flags, merges the root butane config's inline
# references into a single ignition document, and stores the compiled result
# as a podman secret.
#
# Globals:
#   __bash_logger_adapter_env_log_level   Read by bash_logger_adapter_apply_overrides().
# Arguments:
#   See usage().
# Outputs:
#   Logs via the bash-logger-adapter primitives; usage text to stderr on -h/bad options.
# Returns:
#   0 on success; non-zero (via fatal()) on any option, merge, or secret-store failure.
main() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  local -a labels=() secret_mounts=()
  local ignition_secret_postfix="" butane_file="" opt
  local -i OPTIND=1 cli_verbose=0 cli_quiet=0
  while getopts ':s:p:l:f:vqh' opt; do
    case "${opt}" in
      p)
        core::is_option_arg_dup "${opt}" "${ignition_secret_postfix}"
        ignition_secret_postfix="${OPTARG}"
        local -r ignition_secret_postfix
        ;;
      s)
        # -s is inserted via ignition_gen()
        secret_mounts+=("${OPTARG}")
        ;;
      l)
        # -l is inserted as an index before $OPTARG to preserve spacing when
        # passed to podman_secret_create_replace_from_stdin()
        labels+=("-${opt}" "${OPTARG}")
        ;;
      f)
        core::is_option_arg_dup "${opt}" "${butane_file}"
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
        fatal "-${OPTARG} ${ERROR_OPTION_REQUIRED}"
        ;;
      ?)
        usage
        fatal "-${OPTARG} ${ERROR_OPTION_UNKNOWN}"
        ;;
    esac
  done
  shift $((OPTIND - 1))
  # CLI flags take precedence over VERBOSE/QUIET env vars for this invocation
  # (see hack/vendor/bash-logger-adapter/adapter.sh for the general
  # CLI > env > default precedence rule).
  bash_logger_adapter_apply_overrides "${cli_verbose}" "${cli_quiet}" \
    "${__bash_logger_adapter_env_log_level}"
  [[ -z "${butane_file:-}" ]] && { usage; fatal "-f ${ERROR_OPTION_REQUIRED}"; }
  [[ -z "${ignition_secret_postfix:-}" ]] && {
    usage
    fatal "-p ${ERROR_OPTION_REQUIRED}"
  }
  [[ -f "${butane_file}" ]] || { usage; fatal "${ERROR_FILE_NOT_FOUND}: ${butane_file}"; }
  debug "$(declare -p ignition_secret_postfix labels butane_file)"

  # shellcheck disable=SC2034  # ignition_main is populated by name via nameref in ignition_gen_config_merge_inlines()
  local ignition_main
  ignition_gen_config_merge_inlines "${butane_file}" \
    ignition_main \
    secret_mounts \
    || fatal "ignition_gen_config_merge_inlines failed."

  labels+=("-l" "format=ignition")
  podman_secret_create_replace_from_stdin "${labels[@]}" \
    "ignition-${ignition_secret_postfix}" \
    <<< "${ignition_main}" \
    || fatal "podman_secret_create_replace_from_stdin failed."
}

if [[ "${__bash_logger_adapter_sourced:-}" != "true" ]]; then
  declare __bash_logger_adapter_path="hack/vendor/bash-logger-adapter/adapter.sh"
  [[ -f "${__bash_logger_adapter_path}" ]] || {
    printf '%s\n' "failed to find file: ${__bash_logger_adapter_path}" >&2
    exit 1
  }
  # shellcheck source=../vendor/bash-logger-adapter/adapter.sh
  . "${__bash_logger_adapter_path}"
  unset __bash_logger_adapter_path
fi

if [[ "${__bashkit_core_sourced:-}" != "true" ]]; then
  declare __bashkit_core="hack/vendor/bashkit/local/lib/bashkit/core/contract-utils.sh"
  [[ -f "${__bashkit_core}" ]] || fatal "${ERROR_FILE_NOT_FOUND}: ${__bashkit_core}"
  # shellcheck source=../vendor/bashkit/local/lib/bashkit/core/contract-utils.sh
  . "${__bashkit_core}"
  unset __bashkit_core
fi

if [[ "${__hack_lib_podman_secret_sourced:-}" != "true" ]]; then
  declare podman_secrets="hack/lib/podman/podman-secret.sh"
  [[ -f "${podman_secrets}" ]] || {
    printf '%s\n' "failed to find file: ${podman_secrets}" >&2
    exit 1
  }
  # shellcheck source=../lib/podman/podman-secret.sh
  . "${podman_secrets}"
  unset podman_secrets
fi

if [[ "${__hack_lib_ignition_sourced:-}" != "true" ]]; then
  declare ignition_lib="hack/lib/ignition/ignition.sh"
  [[ -f "${ignition_lib}" ]] || fatal "${ERROR_FILE_NOT_FOUND}: ${ignition_lib}"
  # shellcheck source=../lib/ignition/ignition.sh
  . "${ignition_lib}"
  unset ignition_lib
fi

main "$@"
