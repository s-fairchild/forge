# shellcheck shell=bash

declare -r __hack_lib_podman_secrets_create_sourced="true"

# podman_create_replace_secret()
#
# args:
#   * 1) secret_name - string; optional
#       * A default secret name will be generated based on the function name if not provided.
podman_create_replace_secret() {
    local -ri default_secret_name_suffix=$((RANDOM % 100 + 1))
    local -r script_name="$(basename "$0")"
    local -r default_secret_name="${script_name}-${default_secret_name_suffix}"
    local -r secret_name="${1:-$default_secret_name}"

    shift

    local -r input="$(cat)"
    [ -z "$input" ] && fatal "$__fatal_msg_stdin_null"

    # shellcheck disable=SC2128
    podman secret \
            create \
            --replace \
            --label "generated-by=${script_name}" \
            --label "generated-by-function=${FUNCNAME}()" \
            "$secret_name" \
            - \
            <<< "$input"
}

# podman_secret_showsecret()
#
# args:
#   * 1) s - string; podman secret name to be inspected
podman_secret_showsecret() {
    local -r s="${1?$(fatal "\$1 is unset. podman secret name must be provided.")}"

    [ -z "$s" ] && fatal "\$1 cannot be empty string."

    podman secret \
            inspect \
            --showsecret \
            -f '{{.SecretData}}' \
            "$s"
}

# podman_secret_create_from_file()
#
# Pass a directory containing secret files to be created as podman secrets.
# The secret name will be the same as the file it's created from.
#
# args:
#   * 1) src - string; directory containing secret files.
podman_secret_create_from_file() {
    local -r src="${1?'src must be provided.'}"

    [ -d "$src" ] || fatal "\$1 must be a directory. Directory not found: $src"
    pushd "$src" || fatal "failed to pushd into directory: $src"

    for s in *; do
        # TODO troubleshoot saving hash as a label.
        # It's currently getting corrupted.
        #
        # sha512sum_gen "$s" || fatal
        # sha512sum_check "$s" || fatal
        # hash="$(format_hash "$s" | base64)"


        info "Attempting to create (or update) podman secret: $s"

        podman secret \
                create \
                --replace \
                --label component="$(basename "$src")" \
                --label sha512sum="${hash}" \
                "$s" \
                "./$s" \
        || error "failed to create podman secret: $s"
    done

    popd || error "failed to popd back into original directory."
}

declare -r __fatal_msg_stdin_null="stdin input cannot be null."
declare __error_msg_file_not_found="could not find file to source"

if [ "${__lib_opt_bash_utils_logging_sourced:-}" != "true" ]; then
    declare -r shell_utils_logging="hack/lib/opt-bash-utils-logging.sh"

    [ -f "$shell_utils_logging" ] || "$(echo "${__error_msg_file_not_found}: $shell_utils_logging"; exit 1)"
    # shellcheck source=../opt-bash-utils-logging.sh
    . "$shell_utils_logging"
fi
