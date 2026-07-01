# hack/lib/podman/podman-secret.sh
#
# shellcheck shell=bash

declare -r __lib_podman_secret_sourced="true"

declare -ar __empty_array=()

# podman_secret_exists()
#
# Returns 0 if a podman secret with the given name or ID exists, non-zero otherwise.
# Thin wrapper around `podman secret exists` for use in conditional expressions.
#
# args:
#   * 1) secret - string; podman secret name or ID to check.
podman_secret_exists() {
    podman secret exists "$1"
}

# podman_secret_create_replace_from_stdin()
#
# Creates or replaces a podman secret from stdin using `podman secret create --replace`.
# Reads secret data from stdin; aborts if stdin is empty.
# Standard provenance labels (generating file, sourced file, function name) are always
# applied.  Additional caller-supplied labels are appended when labels_extra is set.
#
# args:
#   * 1) secret_name  - string; name of the podman secret to create or replace.
#   * 2) labels_extra - nameref (optional); array of additional label values to apply.
#         Each element is appended as "--label=<value>".  Pass nothing or an empty
#         array to omit extra labels.
podman_secret_create_replace_from_stdin() {
    local -r secret_name="${1?$(fatal "$ERROR_ARG_REQUIRED: \$1")}"
    local -n labels_extra="${2:-__empty_array}"

    local -r input="$(cat)"
    [ -z "$input" ] && fatal "input $ERROR_STDIN_NULL"

    local -a labels=(
        "--label=generated-by-file=$(basename "$0")"
        "--label=generated-by-sourced-file=${BASH_SOURCE[0]}"
        "--label=generated-by-function=${FUNCNAME[0]}()"
    )

    if [ -v labels_extra ]; then
        append_array_with_text labels \
                                labels_extra \
                                "--label="
    fi
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
    local -r s="${1?$(fatal "\$1 is unset. podman secret name must be provided.")}"

    [ -z "$s" ] && fatal "\$1 cannot be empty string."

    podman secret \
            inspect \
            --showsecret \
            -f '{{.SecretData}}' \
            "$s"
}

# podman_secret_name_from_id()
#
# Resolves a podman secret ID to its human-readable name and prints it to stdout
# without a trailing newline.  Aborts if the secret does not exist.
# Used to translate ID arrays (as returned by podman secret create) into names
# before constructing --secret mount options.
#
# args:
#   * 1) id - string; podman secret ID to resolve.
podman_secret_name_from_id() {
    local -r id="${1?$(fatal "\$1 id $ERROR_ARG_REQUIRED")}"

    podman secret exists "$id" || fatal "podman secret $id does not exist."

    local s
    s="$(podman secret inspect -f '{{.Spec.Name}}' "$id")"
    printf '%s' "$s"
}

# podman_secret_create_from_file()
#
# Creates a podman secret for each file path or glob in the src_files array.
# The secret name is the basename of the source file.  Secrets that already exist
# are skipped with a warning — delete the secret manually to force recreation.
# Provenance labels and any caller-supplied extra labels are applied to each secret.
#
# args:
#   * 1) src_files    - nameref; array of file paths or glob patterns to create secrets
#         from.  Each element is expanded and its basename becomes the secret name.
#   * 2) labels_extra - nameref (optional); array of additional label values.
#         Each element is appended as "--label=<value>".
podman_secret_create_from_file() {
    local -n src_files="${1?$(fatal "$ERROR_ARG_REQUIRED: \$1")}"
    # shellcheck disable=SC2034
    local -n labels_extra="${2:-__empty_array}"

    local secret_name
    # shellcheck disable=SC2068
    for f in ${src_files[@]}; do
        secret_name="$(basename "$f")"

        if podman_secret_exists "$secret_name"; then
            warn "podman secret $secret_name already exists. Delete this secret if you intend to update it."
            return
        fi

        local -a labels=(
            "--label=generated-by-file=$(basename "$0")"
            "--label=generated-by-sourced-file=${BASH_SOURCE[0]}"
            "--label=generated-by-function=${FUNCNAME[0]}()"
            "--label=filepath=$f"
        )

        if [ -v labels_extra ]; then
            append_array_with_text labels \
                labels_extra \
                "--label="
        fi
        debug "$(declare -p labels)"

        podman secret \
                create \
                --ignore \
                ${labels[@]} \
                "$secret_name" \
                "$f" \
        || fatal "failed to create podman secret: $f"
    done
}

# gen_secret_mount_opts()
#
# Converts an array of podman secret IDs into `--secret=` mount option strings
# suitable for passing to `podman run`.  Each ID is resolved to its secret name
# via podman_secret_name_from_id() so that the mount path inside the container
# is deterministic regardless of how the ID was obtained.
#
# The generated option format is:
#   --secret=<name>,type=mount,target=<target_dir>/<name>
#
# args:
#   * 1) out        - nameref; empty array that receives the generated option strings.
#   * 2) ids        - nameref; array of podman secret IDs to convert.  Must be non-empty.
#   * 3) target_dir - string; absolute path inside the container under which each secret
#         is mounted (e.g. $__BUTANE_WORKDIR/files/secrets).
gen_secret_mount_opts() {
    # shellcheck disable=SC2034
    local -n out="${1?$(fatal "$ERROR_ARG_REQUIRED: \$1")}"
    local -n ids="${2?$(fatal "$ERROR_ARG_REQUIRED: \$2")}"
    local -r target_dir="${3?$(fatal "$ERROR_ARG_REQUIRED: \$3")}"

    # shellcheck disable=SC2068
    for s in ${ids[@]}; do
        local name
        name="$(podman_secret_name_from_id "$s")"
        out+=("--secret=$name,type=mount,target=$target_dir/$name")
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
    local -r input="$(cat)"
    [ -z "$input" ] && fatal "input $ERROR_STDIN_NULL"

    local -a secrets
    mapfile secrets <<< "$input"
    # shellcheck disable=SC2068
    podman secret inspect --showsecret ${secrets[@]} \
        | jq -r 'map({(.ID): .SecretData}) | add'
}

# # podman_secret_filter_by_label()
# podman_secret_filter_by_label() {
    # local -r label="${1?$(error \$1 $ERROR_)}"
    # # TODO troubleshoot adding podman secrets. Currently it's attempting to pull the secret name as if it is an image.
    # secret_id="$$(podman secret \
        # inspect \
        # $$(podman secret ls -q) \
        # | jq -r '.[] \
        # | select(.Spec.Labels["deployment"] == "installer") \
        # | .Spec.ID')"
# }

if [ "${__bash_utils_base_config_logging_sourced:-}" != "true" ]; then
    declare -r __bash_utils_base_config_logging="hack/vendor/bash-utils/lib/base-config-logging.sh"
    [ -f "$__bash_utils_base_config_logging" ] || { printf '%s\n' "failed to find file: $__bash_utils_base_config_logging" >&2; exit 1; }
    # shellcheck source=../../vendor/bash-utils/lib/base-config-logging.sh
    . "$__bash_utils_base_config_logging"
fi

if [ "${__hack_lib_arrays_sourced:-}" != "true" ]; then
    declare -r __hack_lib_arrays="hack/lib/arrays.sh"
    [ -f "$__hack_lib_arrays" ] || fatal "$ERROR_FILE_SOURCE_FAILED: $__hack_lib_arrays"
    # shellcheck source=../arrays.sh
    . "$__hack_lib_arrays"
fi
