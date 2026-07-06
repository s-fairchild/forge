# hack/lib/podman/podman-secret.sh
#
# shellcheck shell=bash

declare -r __lib_podman_secret_sourced="true"

declare -ar __empty_array=()
declare -r __PODMAN_SECRETS_METADATA_FILENAME="secrets/secrets.json"
declare -r __PODMAN_SECRETS_FILEDRIVER_FILENAME="secrets/filedriver/secretsdata.json"

# podman_secret_exists()
#
# Returns 0 if a podman secret with the given name or ID exists, non-zero otherwise.
# Thin wrapper around `podman secret exists` for use in conditional expressions.
#
# args:
#   * 1) secret - string; podman secret name or ID to check.
podman_secret_exists() {
    debug "Starting ${FUNCNAME[0]}()"
    podman secret exists "$1"
}

usage_podman_secret_create_replace_from_stdin() {
    cat <<USAGE >&2
Usage: podman_secret_create_replace_from_stdin [-l label]... secret_name < input

Creates or replaces a podman secret from stdin using \`podman secret create --replace\`.
Reads secret data from stdin; aborts if stdin is empty. Standard provenance labels
(generating file, sourced file, function name) are always applied.

Options:
    -l label  Additional "key=value" label to apply to the secret.
              May be specified multiple times.
USAGE
}

# podman_secret_create_replace_from_stdin()
#
# Creates or replaces a podman secret from stdin using `podman secret create --replace`.
# Reads secret data from stdin; aborts if stdin is empty.
# Standard provenance labels (generating file, sourced file, function name) are always
# applied.
#
# Options:
#   * -l <label=value> - additional label to apply to the secret. Repeatable.
#
# args:
#   * 1) secret_name - string; name of the podman secret to create or replace.
podman_secret_create_replace_from_stdin() {
    debug "Starting ${FUNCNAME[0]}()"

    local -a extra_labels=()
    local opt OPTIND=1
    while getopts ':l:' opt; do
        case "$opt" in
            l) extra_labels+=("$OPTARG") ;;
            :) usage_podman_secret_create_replace_from_stdin; fatal "-${OPTARG} $ERROR_OPTION_REQUIRED" ;;
            ?) usage_podman_secret_create_replace_from_stdin; fatal "-${OPTARG} $ERROR_OPTION_UNKNOWN" ;;
        esac
    done
    shift $((OPTIND - 1))

    local -r secret_name="${1?$(fatal "$ERROR_ARG_REQUIRED: \$1")}"

    local -r input="$(cat)"
    [ -z "$input" ] && fatal "input $ERROR_STDIN_NULL"

    local -a labels=(
        "--label=generated-by-file=$(basename "$0")"
        "--label=generated-by-sourced-file=${BASH_SOURCE[0]}"
        "--label=generated-by-function=${FUNCNAME[0]}()"
    )

    local l
    for l in "${extra_labels[@]}"; do
        labels+=("--label=$l")
    done
    debug "$(declare -p labels)"

    # shellcheck disable=SC2068
    printf '%s' "$input" \
    | podman secret \
            create \
            --replace \
            ${labels[@]} \
            "$secret_name" \
            - \
    || fatal "failed to create podman secret: $secret_name"
}

# podman_secret_showsecret()
#
# Prints the raw secret data for a named podman secret to stdout.
# Uses `podman secret inspect --showsecret` with the SecretData Go template field.
# Aborts if the secret name argument is missing or empty.
#
# args:
#   * 1) s - string; podman secret name to retrieve data from.
podman_secret_showsecret() {
    debug "Starting ${FUNCNAME[0]}()"
    local -r s="${1?$(fatal "\$1 is unset. podman secret name must be provided.")}"

    [ -z "$s" ] && fatal "\$1 cannot be empty string."

    podman secret \
            inspect \
            --showsecret \
            -f '{{.SecretData}}' \
            "$s"
}

usage_podman_secret_create_from_file() {
    cat <<USAGE >&2
Usage: podman_secret_create_from_file [-l label]... src_files_nameref

Creates a podman secret for each file path or glob in the src_files array. The secret
name is the basename of the source file. Secrets that already exist are skipped with
a warning — delete the secret manually to force recreation. Provenance labels and any
caller-supplied extra labels are applied to each secret.

Options:
    -l label  Additional "key=value" label to apply to each created secret.
              May be specified multiple times.

Arguments:
    src_files_nameref  Name of an array variable holding file paths or glob patterns
                        to create secrets from.
USAGE
}

# podman_secret_create_from_file()
#
# Creates a podman secret for each file path or glob in the src_files array.
# The secret name is the basename of the source file.  Secrets that already exist
# are skipped with a warning — delete the secret manually to force recreation.
# Provenance labels and any caller-supplied extra labels are applied to each secret.
#
# Options:
#   * -l <label=value> - additional label to apply to each created secret.
#                        Repeatable; each value is passed as --label=<value>.
#
# args:
#   * 1) src_files - nameref name; array of file paths or glob patterns to create
#         secrets from.  Each element is expanded and its basename becomes the secret name.
podman_secret_create_from_file() {
    debug "Starting ${FUNCNAME[0]}()"

    local -a extra_labels=()
    local opt OPTIND=1
    while getopts ':l:' opt; do
        case "$opt" in
            l) extra_labels+=("$OPTARG") ;;
            :) usage_podman_secret_create_from_file; fatal "-${OPTARG} $ERROR_OPTION_REQUIRED" ;;
            ?) usage_podman_secret_create_from_file; fatal "-${OPTARG} $ERROR_OPTION_UNKNOWN" ;;
        esac
    done
    shift $((OPTIND - 1))

    local -n src_files="${1?$(fatal "$ERROR_ARG_REQUIRED: \$1")}"

    local secret_name f
    # shellcheck disable=SC2068
    for f in ${src_files[@]}; do
        secret_name="$(basename "$f")"

        if podman_secret_exists "$secret_name"; then
            warn "podman secret $secret_name already exists. Delete this secret if you intend to update it."
            continue
        fi

        local -a labels=(
            "--label=generated-by-file=$(basename "$0")"
            "--label=generated-by-sourced-file=${BASH_SOURCE[0]}"
            "--label=generated-by-function=${FUNCNAME[0]}()"
            "--label=filepath=$f"
        )

        local l
        for l in "${extra_labels[@]}"; do
            labels+=("--label=$l")
        done
        debug "$(declare -p labels)"

        # shellcheck disable=SC2068
        podman secret \
                create \
                --ignore \
                ${labels[@]} \
                "$secret_name" \
                "$f" \
        || fatal "failed to create podman secret: $f"
    done
}

# podman_secret_gen_file_secretsdata()
#
# Generates a secretsdata.json blob in the format expected by the podman file
# secret driver.  Reads a whitespace-separated list of secret names or IDs from
# stdin, inspects each with `podman secret inspect --showsecret`, and produces a
# JSON object mapping each secret ID to its raw secret data.
#
# The output can be written to /var/lib/containers/storage/secrets/filedriver/secretsdata.json
# on a target host to pre-populate the podman secret store without running
# `podman secret create` on that host (e.g. via ignition file injection).
#
# args:
#   * stdin) whitespace-separated list of podman secret names or IDs to include.
#
# stdout) JSON object: { "<id>": "<secret_data>", ... }
podman_secret_gen_file_secretsdata() {
    debug "Starting ${FUNCNAME[0]}()"
    local -r input="$(cat)"
    [ -z "$input" ] && fatal "input $ERROR_STDIN_NULL"

    local -a secrets
    mapfile secrets <<< "$input"
    # shellcheck disable=SC2068
    podman secret inspect --showsecret ${secrets[@]} \
        | jq -r 'map({(.ID): .SecretData}) | add'
}

# podman_secret_filter_by_label()
#
# Prints the names of all podman secrets carrying the given label key/value pair.
# Inspects every existing secret and selects those whose Spec.Labels[label] equals
# value.  (`podman secret ls --filter` does not support label filtering, so the
# match is performed with jq.)
#
# args:
#   * 1) label - string; label key to filter on.
#   * 2) value - string; expected label value.
#
# stdout) Names of matching podman secrets, newline-separated.
podman_secret_filter_by_label() {
    debug "Starting ${FUNCNAME[0]}()"
    local -r label="${1?$(error \$1 "$ERROR_ARG_REQUIRED")}"
    local -r value="${2?$(error \$2 "$ERROR_ARG_REQUIRED")}"
    debug "$(declare -p label)"
    debug "$(declare -p value)"

    local -a secrets
    # shellcheck disable=SC2207
    secrets=($(podman secret ls -q))
    debug "$(declare -p secrets)"

    local names
    # shellcheck disable=SC2068
    if ! names="$(podman secret inspect ${secrets[@]} \
        | jq -r --arg label "$label" --arg value "$value" \
            '.[] | select(.Spec.Labels[$label] == $value) | .Spec.Name')"; then
        error "failed to parse podman secret data with filter: .Spec.Labels[\"$label\"] == \"$value\""
    elif [ -z "$names" ]; then
        error "no podman secret found with filter: .Spec.Labels[\"$label\"] == \"$value\""
    fi

    debug "$(declare -p names)"
    printf "%s" "$names"
}

if [ "${__bash_utils_base_config_logging_sourced:-}" != "true" ]; then
    declare -r __bash_utils_base_config_logging="hack/vendor/bash-utils/lib/base-config-logging.sh"
    [ -f "$__bash_utils_base_config_logging" ] || { printf '%s\n' "failed to find file: $__bash_utils_base_config_logging" >&2; exit 1; }
    # shellcheck source=../../vendor/bash-utils/lib/base-config-logging.sh
    . "$__bash_utils_base_config_logging"
fi

