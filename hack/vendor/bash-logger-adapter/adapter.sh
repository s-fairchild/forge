# shellcheck shell=bash
#
# Compatibility shim that backs the old bash-utils logging API
# (fatal/error/warn/info/debug/log and the ERROR_* message constants) with
# the vendored bash-logger module. Existing call sites across hack/lib,
# hack/bin, and bashkit are unchanged; only the sourcing path in each of them
# points here instead of hack/vendor/bash-utils/lib/base-config-logging.sh.
#
# Verbosity/log-level precedence: CLI flag > environment variable > built-in
# default. This file is `source`d (not exec'd), so it has no argv of its
# own; env vars are read and applied to bash-logger via init_logger
# unconditionally at source time (this preserves every existing caller's
# behavior unchanged). A caller that wants its own CLI flags (e.g. -v/-q
# parsed via its own getopts loop) to take precedence over VERBOSE/QUIET
# must call the public bash_logger_adapter_apply_overrides() function
# *after* it finishes parsing its options, passing whatever it parsed. That
# re-invokes init_logger with the CLI-supplied values taking precedence over
# the env-var-derived defaults captured below. See hack/bin/ignition-gen-main.sh
# for an end-to-end example (-v/-q flags feeding this function).
#
# shellcheck shell=bash disable=SC2034

declare XTRACE=${XTRACE:=0}
(( XTRACE )) && set -x

# Caps bash function-call nesting depth process-wide. This file is sourced by
# every hack/bin and hack/lib script, so it's the one place a cap here
# protects everything. Without it, an accidental call cycle through the
# logging path (e.g. a helper's own "Starting ..." trace calling back into
# log()) recurses silently until the process exhausts memory instead of
# failing fast with a clear error -- 200 is far above this codebase's normal
# call depth (a handful of frames) but far below what it'd take to run a
# system out of memory.
declare -gi FUNCNEST=200

declare -r __bash_logger_adapter_sourced="true"

declare __bash_logger_adapter_local_path="${BASH_SOURCE[0]%/*}"
declare -r __bash_logger_adapter_config_file_default=\
"${__bash_logger_adapter_local_path}/etc/logging.conf"

######################
### Error Messages ###
######################

declare -r ERROR_FILE_NOT_FOUND="file not found"
declare -r ERROR_DIR_NOT_FOUND="directory not found"
declare -r ERROR_FAILED_TO_CREATE_DIR="failed to create directory"
declare -r ERROR_FAILED_TO_CREATE_FILE="failed to create file"
declare -r ERROR_FILE_SOURCE_FAILED="failed to source file"
declare -r ERROR_OPTION_REQUIRED="option must be provided"
declare -r ERROR_OPTION_UNKNOWN="option is unknown"
declare -r ERROR_OPTION_ARG_DUP="[option_argument] can only be specified once"
declare -r ERROR_OPTION_ARG_REQUIRED="[option argument] is required"
declare -r ERROR_VAR_UNSET="variable is unset"
declare -r WARN_VAR_UNSET="${ERROR_VAR_UNSET}"
declare -r ERROR_ARRAY_NO_INDEX="array has no indexes set"
declare -r ERROR_OPERAND_REQUIRED="operand is required"
declare -r ERROR_STRING_EMPTY="string cannot be empty"
declare -r ERROR_STDIN_NULL="stdin cannot be null"
declare -r ERROR_REGEX_FAIL="failed regex match"

# Captured before sourcing bash-logger below: its logging.sh unconditionally
# sets its own global VERBOSE="false" default (a public state variable
# tracking its --verbose flag), which would otherwise clobber a
# caller-supplied VERBOSE=1 env var before we get to read it. These remain
# the env-var tier of the precedence chain; a CLI override (see
# bash_logger_adapter_apply_overrides() below) takes priority over them,
# never the reverse.
declare -r __bash_logger_adapter_env_config_file=\
"${BASH_LOGGER_ADAPTER_CONFIG:-}"
declare -r __bash_logger_adapter_env_verbose="${VERBOSE:-0}"
declare -r __bash_logger_adapter_env_debug="${DEBUG:-0}"
declare -r __bash_logger_adapter_env_quiet="${QUIET:-0}"

if [[ "${__bash_logger_sourced:-}" != "true" ]]; then
  declare __bash_logger_entry="${__bash_logger_adapter_local_path}/../bash-logger/logging.sh"
  [[ -f "${__bash_logger_entry}" ]] || { printf '%s\n' "${ERROR_FILE_NOT_FOUND}: ${__bash_logger_entry}" >&2; exit 1; }
  # shellcheck source=../bash-logger/logging.sh
  . "${__bash_logger_entry}"
  unset __bash_logger_entry
  declare -r __bash_logger_sourced="true"
fi

declare __bash_logger_adapter_env_log_level="${LOG_LEVEL:-${LOG_LEVEL_INFO}}"

#########################################################
### bash-utils API -> bash-logger Compatibility Shims ###
#########################################################

# _bash_logger_adapter_call()
#
# Calls a bash-logger log_* function with `set -e` shielded (see note
# below), then restores the caller's errexit state. Always returns 0,
# matching the bash-utils debug/info/warn/error functions this shim
# replaces (none of which could fail the calling script).
#
# bash-logger 2.5.5's init_logger uses `(( var++ ))`-style arithmetic
# internally (its config-file and CLI-arg parsing loops) that trips `set -e`
# even though the function is designed to return 0 (see
# hack/vendor/bash-logger/logging.sh:535,1167). Several hack/bin entry
# points (ignition-gen-main.sh, k3s-tokens-generate.sh,
# kube-manifests-gen.sh, podman-build.sh) and hack/lib/ignition/serve.sh
# already run under `set -o errexit`, so this shielding is load-bearing
# today, not just future-proofing.
#
# Globals:
#   None.
# Arguments:
#   $@   The bash-logger log_* function (and its arguments) to invoke.
# Outputs:
#   Whatever the invoked log_* function writes.
# Returns:
#   Always 0.
_bash_logger_adapter_call() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  local -i errexit_was_set="0"
  [[ $- == *e* ]] && errexit_was_set="1"
  set +e

  "$@"

  (( errexit_was_set )) && set -e
  return 0
}

# _bash_logger_compat_init([cli_verbose] [cli_quiet])
#
# Builds bash-logger's init_logger option list from the env-var tier
# (captured above) merged with an optional CLI-flag tier, CLI taking
# precedence, then (re-)invokes init_logger. Called once unconditionally
# below (with no args, i.e. env-only) so every existing caller keeps its
# current behavior; called again by bash_logger_adapter_apply_overrides()
# when a caller wants its own parsed CLI flags to win instead.
#
# cli_verbose/cli_quiet are booleans ("1" = flag given on the CLI,
# "0"/unset = not given, fall back to the env var). Like most CLIs (k3s,
# docker, kubectl), these flags can only turn verbosity/quiet ON from the
# CLI tier; there is no CLI way to force them off once an env var has
# turned them on -- QUIET=0/unset is itself already "off".

# _bash_logger_compat_init() {
# }
# _bash_logger_compat_init

# bash_logger_adapter_apply_overrides([cli_verbose] [cli_quiet])
#
# Public entry point for a caller script to give its own CLI flags
# precedence over the VERBOSE/QUIET env vars, per this repo's standard "CLI
# flag > env var > default" precedence. Call this *after* your own getopts
# loop finishes parsing, passing "1" for whichever flags were given on the
# command line (omit or pass "0" for flags not given -- see
# hack/bin/ignition-gen-main.sh for a worked example with its own -v/-q
# options). Safe to call multiple times; each call fully re-derives and
# re-applies bash-logger's init options via _bash_logger_adapter_call().
#
# Globals:
#   __bash_logger_adapter_env_verbose, __bash_logger_adapter_env_debug,
#   __bash_logger_adapter_env_quiet   Env-tier verbosity captured at
#                                     source time.
# Arguments:
#   $1   cli_verbose  "1" if the caller's CLI passed a verbose flag, else
#                      "0".
#   $2   cli_quiet    "1" if the caller's CLI passed a quiet flag, else "0".
#   $3   cli_log_level  Log level to apply absent a verbose/quiet override.
# Outputs:
#   None directly; re-invokes bash-logger's init_logger.
# Returns:
#   1 if any of the 3 required arguments is missing; otherwise the return
#   of init_logger (via _bash_logger_adapter_call, which always returns 0).
bash_logger_adapter_apply_overrides() {
  log "${LOG_LEVEL_DEBUG}" "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 3 "$@" || return 1
  local -ri cli_verbose="$1"
  local -ri cli_quiet="$2"
  local -ri cli_log_level="$3"

  # --level must be listed before --verbose/--quiet: init_logger parses
  # options sequentially and later options win, so putting --level first
  # lets --verbose's forced DEBUG level (and --quiet's console-off
  # behavior) take effect over the configured LOG_LEVEL, matching what a
  # caller means by passing -v/-q. (An earlier version of this file instead
  # threw away --level entirely whenever verbose was set, which was a
  # latent bug, not a documented quirk.)
  #
  # --stderr-level is pinned to DEBUG (the least severe level) so
  # bash-logger routes every log message to stderr, never stdout. Nearly
  # every function across hack/lib, hack/bin, and bashkit opens with a
  # `debug "Starting ${FUNCNAME[0]}(...)"` trace, and some of those
  # functions are called via command substitution (e.g.
  # `app="$(get_app_name "$k")"` in kube-manifests-gen.sh) expecting only
  # their real return value on stdout. bash-logger's own default only sends
  # ERROR-and-worse to stderr, so raising verbosity enough to actually emit
  # those DEBUG/INFO/NOTICE/WARN traces (e.g. LOG_LEVEL=7) previously
  # leaked log lines into stdout and corrupted the captured value. Pinning
  # stderr routing here, once, keeps stdout clean at any verbosity without
  # having to fix every call site individually.
  local -a init_opts=(
    --level "${cli_log_level}"
    --stderr-level "${LOG_LEVEL_DEBUG}"
  )

  # CLI flag > env var: a CLI -v/-q wins outright; otherwise fall back to
  # the env-tier values captured at source time (__bash_logger_adapter_env_*).
  if (( cli_verbose > 0 \
      || __bash_logger_adapter_env_verbose > 0 \
      || __bash_logger_adapter_env_debug > 0 )); then
    init_opts+=(--verbose)
  elif (( cli_quiet > 0 || __bash_logger_adapter_env_quiet > 0 )); then
    init_opts+=(--quiet)
  fi

  _bash_logger_adapter_call init_logger "${init_opts[@]}"
}

# fatal([--status=N] message...)
#
# Logs at FATAL/EMERGENCY level and exits. Defaults to exit status 1; pass
# --status=N (as some callers do) to exit with a specific status instead.
#
# Globals:
#   None.
# Arguments:
#   --status=N | --status N   Optional exit status (default: 1).
#   message...                 Text to log.
# Outputs:
#   The formatted fatal log line.
# Returns:
#   Never returns; exits with the resolved status.
fatal() {
  local status=1
  case "${1:-}" in
    --status=*)
      status="${1#*=}"
      shift
      ;;
    --status)
      shift
      status="${1:-1}"
      shift
      ;;
  esac
  log "${LOG_LEVEL_FATAL}" "$*"
  exit "${status}"
}

# error/warn/info/debug(message...)
#
# Log at the named severity via log() (see below). Unlike fatal(), these
# never exit -- matching the bash-utils functions they replace, none of
# which could fail the calling script.
#
# Globals:
#   None.
# Arguments:
#   message...   Text to log.
# Outputs:
#   The formatted log line at the named level.
# Returns:
#   Always 0 (via log() -> _bash_logger_adapter_call).
error() { log "${LOG_LEVEL_ERROR}" "$*"; }
warn()  { log "${LOG_LEVEL_WARN}" "$*"; }
info()  { log "${LOG_LEVEL_INFO}" "$*"; }
debug() { log "${LOG_LEVEL_DEBUG}" "$*"; }

# sensitive(message...)
#
# Logs a message to the console only -- never to a log file or the system
# journal, regardless of configured sinks. Wraps bash-logger's
# log_sensitive() directly rather than routing through log()/LOG_LEVEL_*,
# since sensitive output isn't a severity level (it hardcodes
# LOG_LEVEL_INFO internally) but a distinct sink policy. Use for
# secrets/tokens that must stay visible in an interactive run but must
# never be persisted.
sensitive() { _bash_logger_adapter_call log_sensitive "$*"; }

declare -r LOG_LEVEL_WARNING="${LOG_LEVEL_WARN}"
declare -r LOG_LEVEL_ERR="${LOG_LEVEL_ERROR}"
declare -r LOG_LEVEL_CRIT="${LOG_LEVEL_CRITICAL}"
declare -r LOG_LEVEL_EMERG="${LOG_LEVEL_EMERGENCY}"

validate_log_level() {
  # Deliberately not core::require_operands here: that helper logs its own
  # "Starting ..." trace via debug() -> log() -> validate_log_level(), which
  # would recurse into this function infinitely -- this is the logging
  # bootstrap itself, so it validates its own operand inline instead.
  [[ -v 1 ]] || return 1
  local level="${1}"
  readonly level="${level^^}"

  local level_keywords="${LOG_LEVEL_DEBUG}|${LOG_LEVEL_NOTICE}|INFO|${LOG_LEVEL_INFO}"
  level_keywords+="|${LOG_LEVEL_WARN}|${LOG_LEVEL_WARNING}|${LOG_LEVEL_ERR}|${LOG_LEVEL_ERROR}"
  level_keywords+="|${LOG_LEVEL_CRIT}|${LOG_LEVEL_CRITICAL}|${LOG_LEVEL_ALERT}"
  level_keywords+="|${LOG_LEVEL_EMERG}|${LOG_LEVEL_EMERGENCY}|${LOG_LEVEL_FATAL}"
  readonly keywords

  if ! [[ ${level} =~ ^(${level_keywords})$ ]]; then
    level="${LOG_LEVEL_INFO}"
  fi

  printf '%s' "$level"
}

# log(level, message...)
#
# Mirrors bash-utils' log(), which took an explicit level as $1. Callers
# that instead pass a bare message (no recognized level) fall through to
# INFO, matching those call sites' intent.
#
# Globals:
#   __bash_logger_adapter_level_keywords   Regex of recognized level keywords.
# Arguments:
#   $1   Optional recognized level keyword; consumed via shift when it matches.
#   $@   Remaining args form the message.
# Outputs:
#   The formatted log line at the resolved level.
# Returns:
#   Always 0 (via bash_logger_adapter::call).
log() {
  local level="${1:-}"

  level="$(validate_log_level "${level}")" && shift

  case "${level}" in
    "${LOG_LEVEL_DEBUG}")
      _bash_logger_adapter_call log_debug "$*"
      ;;
    "${LOG_LEVEL_NOTICE}")
      _bash_logger_adapter_call log_notice "$*"
      ;;
    "${LOG_LEVEL_INFO}"|INFO)
      _bash_logger_adapter_call log_info "$*"
      ;;
    "${LOG_LEVEL_WARN}"|"${LOG_LEVEL_WARNING}")
      _bash_logger_adapter_call log_warn "$*"
      ;;
    "${LOG_LEVEL_ERR}"|"${LOG_LEVEL_ERROR}")
      _bash_logger_adapter_call log_error "$*"
      ;;
    "${LOG_LEVEL_CRIT}"|"${LOG_LEVEL_CRITICAL}")
      _bash_logger_adapter_call log_critical "$*"
      ;;
    "${LOG_LEVEL_ALERT}")
      _bash_logger_adapter_call log_alert "$*"
      ;;
    "${LOG_LEVEL_EMERG}"|"${LOG_LEVEL_EMERGENCY}"|"${LOG_LEVEL_FATAL}")
      _bash_logger_adapter_call log_emergency "$*"
      ;;
    *)
      _bash_logger_adapter_call log_info "$*"
      ;;
  esac
}

set_script_name() {
  core::require_operands 1 "$@" || return 1
  local -r name="$1"

  bash_logger_adapter::call set_script_name "$name"
}

set_log_level() {
  core::require_operands 1 "$@" || return 1
  local -r level="$1"

  bash_logger_adapter::call set_log_level "$level"
}

declare -r BOOLEAN_TRUE="true"
declare -r BOOLEAN_FALSE="false"
declare -r BOOLEAN_ON="on"
declare -r BOOLEAN_OFF="off"
declare -r BOOLEAN_YES="yes"
declare -r BOOLEAN_NO="no"

is_boolean() {
  core::require_operands 1 "$@" || return 1
  local bool="$1"
  readonly bool="${bool,,}"

  local boolean_values="${BOOLEAN_TRUE}|${BOOLEAN_FALSE}|${BOOLEAN_ON}|${BOOLEAN_OFF}"
  boolean_values+="|${BOOLEAN_YES}|${BOOLEAN_NO}"
  readonly boolean_values

  if ! [[ "$bool" =~ ^($boolean_values)$ ]]; then
    error "${1} must match regex: ${boolean_values}"
    core::print_stack_trace
    return 1
  fi
}

set_timezone_utc() {
  core::require_operands 1 "$@" || return 1
  local -r utc="$1"
  is_boolean utc

  _bash_logger_adapter_call set_timezone_utc "$utc"
}

set_log_format() {
  core::require_operands 1 "$@" || return 1
  local -r format="$1"

  _bash_logger_adapter_call set_log_format "$format"
}

set_journal_logging() {
  core::require_operands 1 "$@" || return 1
  local -r journal="$1"
  is_boolean journal

  _bash_logger_adapter_call set_journal_logging "$journal"
}

set_journal_tag() {
  core::require_operands 1 "$@" || return 1
  local -r tag="$1"

  _bash_logger_adapter_call set_journal_tag "$tag"
}

set_syslog_facility() {
  core::require_operands 1 "$@" || return 1
  local -r facility="$1"

  _bash_logger_adapter_call set_syslog_facility "$facility"
}

set_unsafe_allow_ansi_codes() {
  core::require_operands 1 "$@" || return 1
  local -r bool="$1"
  is_boolean "$bool"

  _bash_logger_adapter_call set_unsafe_allow_ansi_codes "$bool"
}

declare __bashkit_local_path="${__bash_logger_adapter_local_path}/../bashkit"
if [[ "${__bashkit_core_sourced:-}" != "true" ]]; then
  declare __bashkit_core="${__bashkit_local_path}/local/lib/bashkit/core/contract-utils.sh"
  [[ -f "${__bashkit_core}" ]] || { printf '%s\n' "error file not found: ${__bashkit_core}" >&2; exit 1; }
  # shellcheck source=../bashkit/local/lib/bashkit/core/contract-utils.sh
  . "${__bashkit_core}"
  unset __bashkit_core
fi

if [[ "${facilities:-}" != "true" ]]; then
  declare facilities="${__bash_logger_adapter_local_path}/facilities.sh"
  [[ -f "$facilities" ]] || { printf '%s\n' "error file not found: ${facilities}" >&2; exit 1; }
  # shellcheck source=facilities.sh
  . "$facilities"
  unset facilities
fi

unset __bash_logger_adapter_local_path __bashkit_local_path

bash_logger_adapter_apply_overrides \
  "${__bash_logger_adapter_env_verbose}" \
  "${__bash_logger_adapter_env_quiet}" \
  "${__bash_logger_adapter_env_log_level}"
