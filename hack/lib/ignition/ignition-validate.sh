# hack/lib/ignition/ignition-validate.sh
#
# Wraps the containerized `ignition-validate` CLI (quay.io/coreos/ignition-validate) so callers
# never need it installed on the host.
# shellcheck shell=bash

declare -r __hack_lib_ignition_validate_sourced="true"
declare -r __IGNITION_VALIDATE_WORKDIR="/data"
declare -r __IGNITION_VALIDATE_FILES_DIR="files"

# usage_ignition_validate()
#
# Prints ignition_validate()'s usage message to stderr.
usage_ignition_validate() {
  cat <<USAGE >&2
Usage: ignition_validate [-s secret]... [-m workdir_mount_src] [-h] [arg...]

Runs ignition-validate in a container with image quay.io/coreos/ignition-validate:release.

Options:
  -s secret              podman secret spec passed verbatim to \`podman run --secret\`.
                         May be specified multiple times.
  -m workdir_mount_src   Host directory bind-mounted read-only at ${__IGNITION_VALIDATE_WORKDIR}.
  -h                     Print this usage message and exit.

Remaining arguments are passed through to the ignition-validate container.

Environment:
  PODMAN_LOG_LEVEL       podman run log level. (default: warn)
USAGE
}

# ignition_validate()
#
# Runs ignition-validate in a container, passing all non-option arguments through to it.
#
# Globals:
#   PODMAN_LOG_LEVEL   Optional. podman run log level.
# Arguments:
#   -s secret              podman secret spec (repeatable).
#   -m workdir_mount_src   Host directory bind-mounted read-only at the container workdir.
#   -h                     Print usage and return 0.
#   arg...                 Passed through to the ignition-validate container.
# Outputs:
#   Writes ignition-validate's stdout/stderr; usage text to stderr on -h/bad options.
# Returns:
#   ignition-validate's exit status; 1 on option-parsing failure.
ignition_validate() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  local -a podman_run_options=()
  local -i OPTIND=1
  local opt workdir_mount_src
  while getopts ':s:m:h' opt; do
    case "${opt}" in
      s)
        podman_run_options+=("--secret=${OPTARG}")
        ;;
      m)
        is_option_arg_dup "${opt}" "${OPTARG}"
        workdir_mount_src="--mount=${OPTARG}"
        local -r workdir_mount_src
        ;;
      h)
        usage_ignition_validate
        return 0
        ;;
      :)
        usage_ignition_validate
        error "-${OPTARG} ${ERROR_OPTION_REQUIRED}"
        return 1
        ;;
      ?)
        usage_ignition_validate
        error "-${OPTARG} ${ERROR_OPTION_UNKNOWN}"
        return 1
        ;;
    esac
  done
  shift $((OPTIND - 1))

  [[ -n "${PODMAN_LOG_LEVEL:-}" ]] && podman_run_options+=("--log-level=${PODMAN_LOG_LEVEL}")
  if [[ -n "${workdir_mount_src:-}" ]]; then
    podman_run_options+=(
      "--mount=type=bind,src=${workdir_mount_src},target=${__IGNITION_VALIDATE_WORKDIR},bind-propagation=rslave,no-dereference,ro=true"
      "--security-opt=label=disable"
    )
  fi

  podman_run_options+=(
    "-i"
    "--rm"
    "--env='IGNITION_*'"
    "--env='IGN_*'"
    "--workdir=${__IGNITION_VALIDATE_WORKDIR}"
  )
  local -r image="quay.io/coreos/ignition-validate:release"
  log_sensitive "$(declare -p image podman_run_options __IGNITION_VALIDATE_WORKDIR)"
  log_sensitive "${FUNCNAME[0]}() options: $*"

  podman run \
    "${podman_run_options[@]}" \
    "${image}" \
    "$@"
}

export -f ignition_validate

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
