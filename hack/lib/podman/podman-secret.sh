# hack/lib/podman/podman-secret.sh
#
# shellcheck shell=bash

declare -r __hack_lib_podman_secret_sourced="true"

declare -r __PODMAN_SECRETS_METADATA_FILENAME="secrets/secrets.json"
declare -r __PODMAN_SECRETS_FILEDRIVER_FILENAME="secrets/filedriver/secretsdata.json"

# podman_secret_exists()
#
# Returns 0 if a podman secret with the given name or ID exists, non-zero otherwise.
# Thin wrapper around `podman secret exists` for use in conditional expressions.
#
# Arguments:
#   $1   Podman secret name or ID to check.
# Returns:
#   0 if the secret exists; `podman secret exists`'s exit status otherwise.
podman_secret_exists() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  podman secret exists "$1"
}

# usage_podman_secret_create_replace_from_stdin()
#
# Prints podman_secret_create_replace_from_stdin()'s usage message to stderr.
usage_podman_secret_create_replace_from_stdin() {
  cat <<USAGE >&2
Usage: podman_secret_create_replace_from_stdin [-l label]... [-h] secret_name < input

Creates or replaces a podman secret from stdin using \`podman secret create --replace\`.
Reads secret data from stdin; aborts if stdin is empty. Standard provenance labels
(generating file, sourced file, function name) are always applied.

Options:
  -l label  Additional "key=value" label to apply to the secret.
            May be specified multiple times.
  -h        Print this usage message and exit.
USAGE
}

# podman_secret_create_replace_from_stdin()
#
# Creates or replaces a podman secret from stdin using `podman secret create --replace`.
# Reads secret data from stdin; aborts if stdin is empty.
# Standard provenance labels (generating file, sourced file, function name) are always
# applied.
#
# Arguments:
#   -l label       Additional "key=value" label to apply to the secret. Repeatable.
#   secret_name    Name of the podman secret to create or replace.
# Outputs:
#   Reads secret data from stdin.
# Returns:
#   Non-zero (via fatal) if the secret name/stdin are missing, or secret creation fails.
podman_secret_create_replace_from_stdin() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  local -a extra_labels=()
  local opt OPTIND=1
  while getopts ':l:h' opt; do
    case "${opt}" in
      h)
        usage_podman_secret_create_replace_from_stdin
        return 0
        ;;
      l)
        extra_labels+=("${OPTARG}")
        ;;
      :)
        usage_podman_secret_create_replace_from_stdin
        fatal "-${OPTARG} ${ERROR_OPTION_REQUIRED}"
        ;;
      ?)
        usage_podman_secret_create_replace_from_stdin
        fatal "-${OPTARG} ${ERROR_OPTION_UNKNOWN}"
        ;;
    esac
  done
  shift $((OPTIND - 1))

  local -r secret_name="${1?$(fatal "${ERROR_OPERAND_REQUIRED}: \$1")}"

  local -r input="$(cat)"
  [[ -z "${input}" ]] && fatal "input ${ERROR_STDIN_NULL}"

  local -a labels=(
    "--label=generated-by-file=$(basename "$0")"
    "--label=generated-by-sourced-file=${BASH_SOURCE[0]}"
    "--label=generated-by-function=${FUNCNAME[0]}()"
  )

  local l
  for l in "${extra_labels[@]}"; do
    labels+=("--label=${l}")
  done
  debug "$(declare -p labels)"

  printf '%s' "${input}" \
    | podman secret \
      create \
      --replace \
      "${labels[@]}" \
      "${secret_name}" \
      - \
    || fatal "failed to create podman secret: ${secret_name}"
}

# podman_secret_showsecret()
#
# Prints the raw secret data for a named podman secret to stdout.
# Uses `podman secret inspect --showsecret` with the SecretData Go template field.
# Aborts if the secret name argument is missing or empty.
#
# Arguments:
#   $1   Podman secret name to retrieve data from.
# Outputs:
#   Writes the secret's raw data to stdout.
# Returns:
#   Non-zero (via fatal) if the secret name is missing or empty.
podman_secret_showsecret() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  local -r s="${1?$(fatal "\$1 is unset. podman secret name must be provided.")}"

  [[ -z "${s}" ]] && fatal "\$1 cannot be empty string."

  podman secret \
    inspect \
    --showsecret \
    -f '{{.SecretData}}' \
    "${s}"
}

# usage_podman_secret_create_from_file()
#
# Prints podman_secret_create_from_file()'s usage message to stderr.
usage_podman_secret_create_from_file() {
  cat <<USAGE >&2
Usage: podman_secret_create_from_file [-l label]... [-h] src_files_nameref

Creates a podman secret for each file path or glob in the src_files array. The secret
name is the basename of the source file. Secrets that already exist are skipped with
a warning — delete the secret manually to force recreation. Provenance labels and any
caller-supplied extra labels are applied to each secret.

Options:
  -l label  Additional "key=value" label to apply to each created secret.
            May be specified multiple times.
  -h        Print this usage message and exit.

Arguments:
  src_files_nameref  Name of an array variable holding file paths or glob patterns
                     to create secrets from.
USAGE
}

# podman_secret_create_from_file()
#
# Creates a podman secret for each file path or glob in the src_files array.
# The secret name is the basename of the source file. Secrets that already exist
# are skipped with a warning — delete the secret manually to force recreation.
# Provenance labels and any caller-supplied extra labels are applied to each secret.
#
# Arguments:
#   -l label       Additional "key=value" label to apply to each created secret.
#                  Repeatable; each value is passed as --label=<value>.
#   src_files      Nameref name; array of file paths or glob patterns to create
#                  secrets from. Each element is expanded and its basename becomes
#                  the secret name.
# Outputs:
#   Warns to stderr for each source file whose secret already exists.
# Returns:
#   Non-zero on bad options, a missing operand, or a failed secret creation.
podman_secret_create_from_file() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  local -a extra_labels=()
  local opt OPTIND=1
  while getopts ':l:h' opt; do
    case "${opt}" in
      l)
        extra_labels+=("${OPTARG}")
        ;;
      h)
        usage_podman_secret_create_from_file
        return 0
        ;;
      :)
        usage_podman_secret_create_from_file
        error "-${OPTARG} ${ERROR_OPTION_ARG_REQUIRED}"
        return 1
        ;;
      ?)
        usage_podman_secret_create_from_file
        error "-${OPTARG} ${ERROR_OPTION_UNKNOWN}"
        return 1
        ;;
    esac
  done
  shift $((OPTIND - 1))

  core::require_operands 1 "$@" || return 1
  local -n src_files="$1"

  local secret_name f
  for f in "${src_files[@]}"; do
    secret_name="$(basename "${f}")"

    if podman_secret_exists "${secret_name}"; then
      warn "podman secret ${secret_name} already exists." \
        "Delete this secret if you intend to update it."
      continue
    fi

    local -a labels=(
      "--label=generated-by-file=$(basename "$0")"
      "--label=generated-by-sourced-file=${BASH_SOURCE[0]}"
      "--label=generated-by-function=${FUNCNAME[0]}()"
      "--label=filepath=${f}"
    )

    local l
    for l in "${extra_labels[@]}"; do
      labels+=("--label=${l}")
    done
    debug "$(declare -p labels)"

    podman secret \
      create \
      --ignore \
      "${labels[@]}" \
      "${secret_name}" \
      "${f}" \
      || fatal "failed to create podman secret: ${f}"
  done
}

# podman_secret_gen_file_secretsdata()
#
# Generates a secretsdata.json blob in the format expected by the podman file
# secret driver. Reads a whitespace-separated list of secret names or IDs from
# stdin, inspects each with `podman secret inspect --showsecret`, and produces a
# JSON object mapping each secret ID to its raw secret data.
#
# The output can be written to /var/lib/containers/storage/secrets/filedriver/secretsdata.json
# on a target host to pre-populate the podman secret store without running
# `podman secret create` on that host (e.g. via ignition file injection).
#
# Arguments:
#   (stdin)   Whitespace-separated list of podman secret names or IDs to include.
# Outputs:
#   Writes a JSON object to stdout: { "<id>": "<secret_data>", ... }
# Returns:
#   1 if stdin is a TTY (i.e. nothing was piped in).
podman_secret_gen_file_secretsdata() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  local -r input="$(cat)"
  if [[ -t 0 ]]; then
    error "${ERROR_STDIN_NULL}"
    return 1
  fi

  local -a secrets
  mapfile secrets <<< "${input}"
  podman secret inspect --showsecret "${secrets[@]}" \
    | jq -r 'map({(.ID): .SecretData}) | add'
}

# podman_secret_filter_by_label()
#
# Prints the names of all podman secrets carrying the given label key/value pair.
# Inspects every existing secret and selects those whose Spec.Labels[label] equals
# value. (`podman secret ls --filter` does not support label filtering, so the
# match is performed with jq.)
#
# Arguments:
#   $1   Label key to filter on.
#   $2   Expected label value.
# Outputs:
#   Writes matching podman secret names to stdout, newline-separated.
# Returns:
#   1 if the jq filter fails to parse, or no secret matches.
podman_secret_filter_by_label() {
  debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 2 "$@" || return 1
  local -r label="$1"
  local -r value="$2"
  debug "$(declare -p label)"
  debug "$(declare -p value)"

  local -a secrets
  readarray -t secrets < <(podman secret ls -q)
  debug "$(declare -p secrets)"

  local names
  if ! names="$(podman secret inspect "${secrets[@]}" \
    | jq -r --arg label "${label}" --arg value "${value}" \
      '.[] | select(.Spec.Labels[$label] == $value) | .Spec.Name')"; then
    error "failed to parse podman secret data with filter:" \
      ".Spec.Labels[\"${label}\"] == \"${value}\""
    return 1
  elif [[ -z "${names}" ]]; then
    error "no podman secret found with filter:" \
      ".Spec.Labels[\"${label}\"] == \"${value}\""
    return 1
  fi

  debug "$(declare -p names)"
  printf "%s" "${names}"
}

if [[ "${__bash_logger_adapter_sourced:-}" != "true" ]]; then
  declare __bash_logger_adapter_path="hack/vendor/bash-logger-adapter/adapter.sh"
  [[ -f "${__bash_logger_adapter_path}" ]] || { printf '%s\n' "failed to find file: ${__bash_logger_adapter_path}" >&2; exit 1; }
  # shellcheck source=../../vendor/bash-logger-adapter/adapter.sh
  . "${__bash_logger_adapter_path}"
  unset __bash_logger_adapter_path
fi

if [[ "${__bashkit_core_sourced:-}" != "true" ]]; then
  declare __bashkit_core="hack/vendor/bashkit/local/lib/bashkit/core/contract-utils.sh"
  [[ -f "${__bashkit_core}" ]] || fatal "${ERROR_FILE_NOT_FOUND}: ${__bashkit_core}"
  # shellcheck source=../../vendor/bashkit/local/lib/bashkit/core/contract-utils.sh
  . "${__bashkit_core}"
  unset __bashkit_core
fi
