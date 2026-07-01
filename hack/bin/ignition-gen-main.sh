#!/bin/bash
# Recursively generate all ignition files

[ "${XTRACE:-0}" -eq 1 ] && set -x

set -o nounset \
    -o errexit \
    -o pipefail \
    -o noclobber \
    -o hashall

main() {
    debug "Starting ${FUNCNAME[0]}()"
    local -r butane_main="${1?$(fatal "\$1 butane_main $ERROR_ARG_REQUIRED")}"
    local -r secrets_env="${2:-}"

    if [ -n "$secrets_env" ]; then
        [ -f "$secrets_env" ] || fatal "$ERROR_FILE_NOT_FOUND"
        info "Sourcing $secrets_env"
        # shellcheck source=../../deploy/butane/base/secrets-example.env
        . "$secrets_env" || fatal "$ERROR_FILE_SOURCE_FAILED: $secrets_env"
    fi

    config_layer="$(basename "$(dirname "$butane_main")")"
    local -a secret_labels_extra=(
        "deployment=$config_layer"
    )

    local -a secret_ids
    if [ -v SECRET_FILES ]; then
        info "SECRET_FILES array is set with elements. Creating podman secrets from array items."
        debug "$(declare -p SECRET_FILES)"

        # shellcheck disable=SC2207,SC2034
        secret_ids=($(podman_secret_create_from_file SECRET_FILES secret_labels_extra))
        debug "$(declare -p secret_ids)"
    fi

    if [ -v SECRET_IDS ]; then
        # shellcheck disable=SC2068
        for id in ${SECRET_IDS[@]}; do
            if podman secret exists "$id" > /dev/null 2>&1; then
                info "Adding podman secret: $id"
                secret_ids+=("$id")
            else
                error "podman secret \"$id\" does not exist. Skipping."
            fi
        done
    fi

    # shellcheck disable=SC2034
    local ignition_main
    ignition_gen_config_merge_inlines "$butane_main" \
                                    ignition_main \
                                    secret_ids

    secret_labels_extra+=("type=ignition")
    local -r ignition_secret_name="$config_layer-ignition"
    podman_secret_create_replace_from_stdin "$ignition_secret_name" \
                                            secret_labels_extra \
                                            <<< "$ignition_main"
}

if [ "${__bash_utils_base_config_logging_sourced:-}" != "true" ]; then
    declare -r __bash_utils_base_config_logging="hack/vendor/bash-utils/lib/base-config-logging.sh"
    [ -f "$__bash_utils_base_config_logging" ] || { printf '%s\n' "failed to find file: $__bash_utils_base_config_logging" >&2; exit 1; }
    # shellcheck source=../lib/logging.sh
    . "$__bash_utils_base_config_logging"
fi

if [ "${__lib_podman_secret_sourced:-}" != "true" ]; then
    declare -r podman_secrets="hack/lib/podman/podman-secret.sh"
    [ -f "$podman_secrets" ] || fatal "$ERROR_FILE_NOT_FOUND: $podman_secrets"
    # shellcheck source=../lib/podman/podman-secret.sh
    . "$podman_secrets"
fi

if [ "${__ignition_sourced:-}" != "true" ]; then
    declare -r ignition_lib="hack/lib/ignition/ignition.sh"
    [ -f "$ignition_lib" ] || fatal "$ERROR_FILE_NOT_FOUND: $ignition_lib"
    # shellcheck source=../lib/ignition/ignition.sh
     . "$ignition_lib"
fi

main "$@"
