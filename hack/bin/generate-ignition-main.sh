#!/bin/bash
# Recursively generate all ignition files

[[ "${XTRACE:-0}" -eq 1 ]] && set -x

set -o noclobber

usage() {
  set_script_name "${SCRIPT_NAME:-}:${FUNCNAME[0]}"
  cat <<USAGE >&2
Usage: ${0##*/} -f butane_file -p ignition_secret_postfix [-s secret_name]...
                 [-l label]... [-h]

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
  -l label                   Additional "key=value" label to attach to the
                             ignition-<ignition_secret_postfix> secret. May
                             be specified multiple times.
  -h                         Print this help message and exit.
USAGE
}

# main()
#
# Entry point: parses CLI flags, merges the root butane config's inline
# references into a single ignition document with
# ignition::gen_config_merge_inlines, and stores the compiled result as the
# podman secret ignition-<ignition_secret_postfix> with
# podman::secret_create_replace_from_stdin, labeled format=ignition.
#
# Globals:
#   None.
# Arguments:
#   See usage(). -v and -q are also accepted, but ignored.
# Outputs:
#   Log lines; usage text to stderr on -h/bad options.
# Returns:
#   0 on success; exits 0 on -h; non-zero (via log_fatal or fatal) on any
#   option, merge, or secret-store failure.
main() {
  set_script_name "${SCRIPT_NAME:-}:${FUNCNAME[0]}"
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  local -a labels=() secret_mounts=()
  local ignition_secret_postfix="" butane_file="" opt
  local -i OPTIND=1
  while getopts ':s:p:l:f:vqh' opt; do
    case "${opt}" in
      p)
        core::is_option_arg_dup "${opt}" "${ignition_secret_postfix}"
        ignition_secret_postfix="${OPTARG}"
        ;;
      s) secret_mounts+=("${OPTARG}"); ;;
      l) labels+=("-${opt}" "${OPTARG}"); ;;
      f)
        core::is_option_arg_dup "${opt}" "${butane_file}"
        butane_file="${OPTARG}"
        ;;
      h) usage; return 0; ;;
      :)
        usage
        core::fail "-${OPTARG} operand is required." || return
        ;;
      ?)
        usage
        core::fail "-${OPTARG} option is unknown." || return
        ;;
    esac
  done
  shift $((OPTIND - 1))
  readonly ignition_secret_postfix butane_file

  if [[ -z "${butane_file}" ]]; then
    usage
    core::fail "-f option must be provided." || return
  elif [[ -z "${ignition_secret_postfix}" ]]; then
    usage
    core::fail "-p option must be provided." || return
  elif [[ ! -f "${butane_file}" ]]; then
    usage
    core::fail "file not found: ${butane_file}" || return
  fi
  log_debug "$(declare -p ignition_secret_postfix labels butane_file)"

  # shellcheck disable=SC2034  # ignition_main is populated by name via nameref in ignition::gen_config_merge_inlines()
  local ignition_main
  ignition::gen_config_merge_inlines "${butane_file}" \
    ignition_main \
    secret_mounts \
    || core::fail "ignition_gen_config_merge_inlines failed." \
      || return

  labels+=("-l" "format=ignition")
  podman::secret_create_replace_from_stdin "${labels[@]}" \
    "ignition-${ignition_secret_postfix}" \
    <<< "${ignition_main}" \
    || core::fail "podman::secret_create_replace_from_stdin failed." \
      || return
}

# shellcheck source=../vendor/bashkit/local/lib/bashkit/os/bk-bootstrap.sh
. "${BASH_SOURCE[0]%/*}/../vendor/bashkit/local/lib/bashkit/os/bk-bootstrap.sh"

# shellcheck source=../vendor/bash-logger/logging.sh
. /dev/null
# shellcheck source=../vendor/bashkit/local/lib/bashkit/core/logger-utils.sh
. /dev/null
import core/logger-utils.sh
# shellcheck source=../vendor/bashkit/local/lib/bashkit/core/contract-utils.sh
. /dev/null
import core/contract-utils.sh
# shellcheck source=../vendor/bashkit/local/lib/bashkit/ignition/ignition.sh
import ignition/ignition.sh
# shellcheck source=../vendor/bashkit/local/lib/bashkit/podman/podman-secret.sh
. /dev/null
import podman/podman-secret.sh

core::logger_init --name "$(basename "$0")"

main "$@"
