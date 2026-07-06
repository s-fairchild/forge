#!/bin/bash

set -o nounset \
    -o errexit \
    -o pipefail \
    -o noclobber \
    -o hashall

[ "${XTRACE:-0}" -eq 1 ] && set -x

# main()
#
# Generates k3s cluster authentication tokens as podman secrets and produces
# a secretsdata.json for the podman file secret driver.
#
# For each token name in k3s_tokens (k3s-token, k3s-agent-token): if the
# podman secret does not already exist, a 64-character hex token is generated
# and stored as a podman secret.  Existing secrets are left unchanged with a
# warning — delete the secret manually before re-running to rotate.
#
# After token generation, a secretsdata.json blob is produced by inspecting
# all generated secrets and written as a podman secret under secretsdata_name.
# This JSON is the format consumed by the podman file secret driver and can be
# deployed directly to /var/lib/containers/storage/secrets/filedriver/ on a
# remote host via ignition (see deploy/butane/overlays/prod/etc-containers-secrets.bu).
#
# args:
#   * 1) secretsdata_name - string; name for the podman secret that will hold
#         the generated secretsdata.json file driver blob.
#
# env:
#   * XTRACE=1 - enable bash xtrace for this script.
main() {
    local -a podman_secret_create_options=("--replace")
    local prefix=""
    while getopts ':l:p:' opt; do
        case "$opt" in
            l)
                debug "appending ${OPTARG} to podman_secret_create_options"
                podman_secret_create_options+=(--label="${OPTARG}")
                ;;
            p)
                prefix="${OPTARG}"
                ;;
            :)
                # usage
                fatal "${ERROR_OPTION_REQUIRED}: -${OPTARG}"
                ;;
            ?)
                # usage
                fatal "${ERROR_OPTION_UNKNOWN}: -${OPTARG}"
                ;;
        esac
    done
    [ -z "${prefix:-}" ] && fatal "$ERROR_OPTION_REQUIRED: -p"

    local -r prefix podman_secret_create_options
    debug "$(declare -p prefix podman_secret_create_options)"

    k3s_tokens=(
        k3s-token
        k3s-token-agent
    )

    info "Creating/Replacing podman secrets within podman container."
    # shellcheck disable=SC2068
    for s in ${k3s_tokens[@]}; do
        info "Creating podman secret $s within podman container."
        podman_container secret \
                         create \
                         ${podman_secret_create_options[@]} \
                         "$s" \
                         - \
                         < <(k3s_gen_token) || fatal
    done

    local -Ar podman_filedriver_files=(
        ["${prefix}-secrets.json"]="$__PODMAN_SECRETS_METADATA_FILENAME"
        ["${prefix}-secretsdata.json"]="$__PODMAN_SECRETS_FILEDRIVER_FILENAME"
    )

    info "Creating podman secrets on the host using filedriver json files within the podman container graphroot."
    # shellcheck disable=SC2068
    for s in ${!podman_filedriver_files[@]}; do
        info "Creating/Replacing podman secret $s from volume=$__PODMAN_CONTAINER_VOLUME_GRAPHROOT_USER_PODMAN, file=${podman_filedriver_files[$s]}"

        podman secret \
            create \
            ${podman_secret_create_options[@]} \
            "$s" \
            - < <(podman_volume_export_untar_stdout "$__PODMAN_CONTAINER_VOLUME_GRAPHROOT_USER_PODMAN" \
                                                    "${podman_filedriver_files["$s"]}")
    done
}

if [ "${__hack_env_vendor_sourced:-}" != "true" ]; then
    declare __hack_env_vendor="hack/env/vendor.env"
    [ -f "$__hack_env_vendor" ] || { printf '%s\n' "failed to find file: $__hack_env_vendor" >&2; exit 1; }
    # shellcheck source=../env/vendor.env
    . "$__hack_env_vendor"
    unset __hack_env_vendor
fi

if [ "${__hack_lib_k3s_gen_token_sourced:-}" != "true" ]; then
    declare __hack_lib_k3s_gen_token="hack/lib/k3s/k3s-gen-token.sh"
    [ -f "$__hack_lib_k3s_gen_token" ] || fatal "$ERROR_FILE_NOT_FOUND: $__hack_lib_k3s_gen_token"
    # shellcheck source=../lib/k3s/k3s-gen-token.sh
    . "$__hack_lib_k3s_gen_token"
    unset __hack_lib_k3s_gen_token
fi

if [ "${__lib_podman_sourced:-}" != "true" ]; then
    declare __lib_podman_podman="hack/lib/podman/podman.sh"
    [ -f "$__lib_podman_podman" ] || fatal "$ERROR_FILE_NOT_FOUND: $__lib_podman_podman"
    # shellcheck source=../lib/podman/podman.sh
    . "$__lib_podman_podman"
    unset __lib_podman_podman
fi

main "$@"
