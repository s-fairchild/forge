#!/bin/bash
# Recursively generate all ignition files

set -o nounset \
    -o errexit \
    -o pipefail \
    -o noclobber \
    -o hashall

main() {
    local -r butane_main="${1?$(fatal "\$1 butane_main $ERROR_ARG_NOT_PROVIDED")}"
    local -r secrets_env="${2:-}"

    if [ -n "$secrets_env" ]; then
        [ -f "$secrets_env" ] || fatal "$ERROR_FILE_NOT_FOUND"
        info "Sourcing $secrets_env"
        # shellcheck source=../../deploy/butane/base/secrets.env
        . "$secrets_env" || fatal "$ERROR_FILE_SOURCE_FAILED: $secrets_env"
    fi

    config_layer="$(basename "$(dirname "$butane_main")")"
    local -a secret_labels_extra=(
        "config=$config_layer"
    )

    # TODO mount secret_ids to butane during ignition generation to include local files mounted as secrets.
    local -a secret_ids
    if [ -v SECRET_KEYS ]; then
        info "SECRET_KEYS array is set with elements. Creating podman secrets from array items."
        debug "$(declare -p SECRET_KEYS)"

        # shellcheck disable=SC2207,SC2034
        secret_ids=($(podman_secret_create_from_file SECRET_KEYS secret_labels_extra))
        debug "$(declare -p secret_ids)"
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

if [ "${__lib_opt_bash_utils_logging_sourced:-}" != "true" ]; then
    declare -r lib_opt_bash_utils_logging="hack/lib/opt-bash-utils-logging.sh"
    [ -f "$lib_opt_bash_utils_logging" ] || "$(echo "failed to find file: $lib_opt_bash_utils_logging"; exit 1)"

    # shellcheck source=../lib/opt-bash-utils-logging.sh
    . "$lib_opt_bash_utils_logging" || "$(echo "failed to source file: $lib_opt_bash_utils_logging"; exit 1)"
fi

if [ "${__hack_lib_podman_secrets_create_sourced:-}" != "true" ]; then
    declare -r podman_secrets="hack/lib/podman/podman-secret.sh"
    [ -f "$podman_secrets" ] || fatal "$ERROR_FILE_NOT_FOUND: $podman_secrets"

    # shellcheck source=../lib/podman/podman-secret.sh
    . "$podman_secrets" || fatal "$ERROR_FILE_SOURCE_FAILED: $podman_secrets"
fi

if [ "${__ignition_sourced:-}" != "true" ]; then
    declare -r ignition_lib="hack/lib/ignition/ignition.sh"
    [ -f "$ignition_lib" ] || fatal "$ERROR_FILE_NOT_FOUND: $ignition_lib"

    # shellcheck source=../lib/ignition/ignition.sh
     . "$ignition_lib" || fatal "$ERROR_FILE_SOURCE_FAILED: $ignition_lib"
fi

[ "${XTRACE:-}" == "true" ] && set -o xtrace

main "$@"
