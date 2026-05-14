# hack/lib/podman/podman-secret.sh
#
# shellcheck shell=bash

declare -r __hack_lib_podman_secrets_create_sourced="true"

# podman_secret_create_replace_from_stdin()
#
# args:
#   * 1) secret_name - string; name of podman secret to be created
#   * 2)
podman_secret_create_replace_from_stdin() {
    local -r secret_name="${1?$(fatal "\$1 secret_name $ERROR_ARG_NOT_PROVIDED")}"
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
    podman secret \
            create \
            --replace \
            ${labels[@]} \
            "$secret_name" \
            - \
            <<< "$input" \
    || fatal "failed to create podman secret: $secret_name"
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

# podman_secret_name_from_id()
#
# args:
#   * 1) id - string; podman secret id to get name from
podman_secret_name_from_id() {
    local -r id="${1?$(fatal "\$1 id $ERROR_ARG_NOT_PROVIDED")}"

    podman secret exists "$id" || fatal "podman secret $id does not exist."

    s="$(podman secret \
            ls \
            -f ID="$id" \
            --format '{{.Name}}')"

    # return secret name without ending \n (appended by podman secret ls).
    echo -n "$s"
}

# podman_secret_create_from_file()
#
# Pass a directory containing secret files to be created as podman secrets.
# The secret name will be the same as the file it's created from.
#
# args:
#   * $1) src_files - nameref; directory containing secret files.
#   * $2) key_ids - nameref, array; Optional. Array to update with podman secret key ids.
podman_secret_create_from_file() {
    local -n src_files="${1?$(fatal "\$1 src_files $ERROR_ARG_NOT_PROVIDED")}"
    # shellcheck disable=SC2034
    local -n labels_extra="${2:-__empty_array}"

    local secret_name
    # shellcheck disable=SC2068
    for f in ${src_files[@]}; do
        secret_name="$(basename "$f")"
        # secret_name="$(format_podman_secret_name "$f_name")"

        if podman secret exists "$secret_name"; then
            warn "podman secret $secret_name already exists. Delete this secret if you intend to update it."
        else
            info "Creating podman secret $secret_name from file $f"
        fi

        labels=(
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

# format_podman_secret_name()
#
# Replace characters that are not valid environment variable identifiers
# So that mounting a secret as type=env works
#
# args:
#   * $1) n - string; podman secret name to format.
format_podman_secret_name() {
    local n="${1//-/_}"
    n="${n//./_}"

    echo -n "$n"
}

# gen_secret_mount_opts()
#
# Converts an array of podman secret IDs into an array of --secret=$secret_name,type=mount=target=$__BUTANE_WORKDIR/files/secrets/$secret_name
# podman secret IDs will be converted to the secret names for predictable file mounts within containers.
#
# args:
#   * 1) out - nameref; nameref to set (empty) array. Generated secret mount options will be assigned to out.
#   * 2) secrets - nameref; nameref to an array of podman secret IDs.
gen_secret_mount_opts() {
    # shellcheck disable=SC2034
    local -n out="${1?$(fatal "$ERROR_ARG_NOT_PROVIDED")}"
    local -n ids="${2:-__empty_array}"
    local -r target_dir="${3?$(fatal "\$3 target_dir $ERROR_ARG_NOT_PROVIDED")}"

    [ -v ids ] || fatal "\$2 secrets=\"${ids[*]}\" secrets array must contain elements."

    local -a arr
    # Due to complex formatting of the --secret options, it's simplest to append to secrets one secret at a time.
    # This way I can use prefix and append to the extra string using the secret name.
    # shellcheck disable=SC2068
    for s in ${ids[@]}; do
        arr=("$(podman_secret_name_from_id "$s")")
        append_array_with_text out \
                                arr \
                                "--secret=${arr[0]},type=mount,target=$target_dir/"
    done
}


if [ "${__lib_opt_bash_utils_logging_sourced:-}" != "true" ]; then
    declare -r __shell_utils_logging="hack/lib/opt-bash-utils-logging.sh"
    [ -f "$__shell_utils_logging" ] || "$(echo "failed to find file: $__shell_utils_logging"; exit 1)"

    # shellcheck source=../opt-bash-utils-logging.sh
    . "$__shell_utils_logging" || "$(echo "failed to find file: $__shell_utils_logging"; exit 1)"
fi

if [ "${__hack_lib_lib_sourced:-}" != "true" ]; then
    declare -r __hack_lib_lib="hack/lib/lib.sh"
    [ -f "$__hack_lib_lib" ] || fatal "$ERROR_FILE_NOT_FOUND: $__hack_lib_lib"

    # shellcheck source=../lib.sh
    . "$__hack_lib_lib"
fi

if [ "${__hack_lib_ignition_constants_sourced:-}" != "true" ]; then
    declare -r __hack_lib_ignition_constants="hack/lib/ignition/constants.env"
    [ -f "$__hack_lib_ignition_constants" ] || fatal "$ERROR_FILE_NOT_FOUND: $__hack_lib_ignition_constants"

    # shellcheck source=constants.env
    . "$__hack_lib_ignition_constants" || fatal "$ERROR_FILE_SOURCE_FAILED: $__hack_lib_ignition_constants"
fi
