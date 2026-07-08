#!/bin/bash
# Recursively generate all ignition files

[ "${XTRACE:-0}" -eq 1 ] && set -x

set -o nounset \
    -o errexit \
    -o pipefail \
    -o noclobber \
    -o hashall

usage() {
    cat <<USAGE >&2
Usage: ${0##*/} -b butane_main [-n ignition_secret_name] [-l label]... [-e secrets_env]... [-h]

Recursively compile a root butane config, merging its inline references,
and store the resulting ignition JSON as a podman secret.

Options:
    -b butane_main           Path to the root butane config to compile and merge. (required)
    -n ignition_secret_name  Name of the podman secret to store the generated ignition JSON
                              under. (default: parent directory name of butane_main)
    -l label                 Additional "key=value" label to attach to secrets created
                              during generation. May be specified multiple times.
    -e secrets_env           Path to an env file to source before generation, declaring
                              SECRET_FILES and/or SECRET_IDS. May be specified multiple times.
    -h                       Print this help message and exit.
USAGE
}

fatal_duplicate_option() { fatal "-${1?$(fatal "\$1 $ERROR_ARG_REQUIRED")} can only be specified once."; }

main() {
    debug "Starting ${FUNCNAME[0]}()"

    local -a labels=() secret_envs=()
    local ignition_secret_name="" butane_main="" opt 
    local -i OPTIND=1
    while getopts ':n:l:e:b:h' opt; do
        case "$opt" in
            h)
                usage
                exit 0
                ;;
            n)
                [ -z "$ignition_secret_name" ] || fatal_duplicate_option "$OPTARG"
                ignition_secret_name="${OPTARG}"
                debug "$(declare -p ignition_secret_name)"
                ;;
            l)
                # -l is inserted as an index before $OPTARG to preserve spacing when passed to podman_secret_create_replace_from_stdin
                labels+=("-${opt}" "$OPTARG")
                debug "$(declare -p labels)"
                ;;
            e)
                secret_envs+=("$OPTARG")
                debug "$(declare -p secret_envs)"
                ;;
            b)
                [ -z "$butane_main" ] || fatal_duplicate_option "$OPTARG"
                butane_main="${OPTARG}"
                debug "$(declare -p butane_main)"
                ;;
            :)
                usage
                fatal "-${OPTARG} $ERROR_OPTION_REQUIRED"
                ;;
            ?)
                usage
                fatal "-${OPTARG} $ERROR_OPTION_UNKNOWN"
                ;;
        esac
    done
    shift $((OPTIND - 1))

    local config_layer
    config_layer="$(basename "$(dirname "$butane_main")")"

    info "butane_main=${butane_main?$(usage; fatal "-b is required.")}"
    info "ignition_secret_name=${ignition_secret_name:="$config_layer-ignition"}"
    unset config_layer
    debug "secret_envs=${secret_envs[*]}" 
    debug "labels=${secret_envs[*]}" 

    source_env_files secret_envs
    unset secret_envs
    # shellcheck disable=SC2034
    local -a secrets=()
    get_secrets_from_env secrets
    debug "$(declare -p secrets)"

    # shellcheck disable=SC2034
    local ignition_main
    ignition_gen_config_merge_inlines "$butane_main" \
                                    ignition_main \
                                    secrets
    unset secrets butane_main

    labels+=("-l" "format=ignition")
    # shellcheck disable=SC2068
    podman_secret_create_replace_from_stdin ${labels[@]} \
                                            "$ignition_secret_name" \
                                            <<< "$ignition_main"
    unset ignition_main ignition_secret_name labels
}

# get_secrets_from_env()
get_secrets_from_env() {
    local -n names="${1?$(fatal "\$1 $ERROR_ARG_REQUIRED")}"
    local -r config_env="${2:-}"

    [ -z "$config_env" ] && warn "config_env was not specified. label env= will be empty."
    [[ ${!names@a} == *a* ]] || fatal "${!names} must be an indexed array."

    local -r warn_msg_suffix="is unset or unpopulated. No files were processed."
    if [ -v SECRET_FILES ]; then
        debug "$(declare -p SECRET_FILES)"
        # TODO directly add the secret IDs returned here.
        podman_secret_create_from_file -l "env=$config_env" SECRET_FILES
        local f
        # shellcheck disable=SC2068
        for f in ${SECRET_FILES[@]}; do
            names+=("$(basename "$f")")
        done
    else
        warn "SECRET_FILES $warn_msg_suffix"
    fi

    if [ -v SECRET_IDS ]; then
        # shellcheck disable=SC2068
        for id in ${SECRET_IDS[@]}; do
            if podman secret exists "$id" > /dev/null 2>&1; then
                info "Adding podman secret: $id"
                names+=("$(podman secret inspect -f '{{.Spec.Name}}' "$id")")
            else
                error "podman secret \"$id\" does not exist. Skipping."
            fi
        done
    else
        warn "SECRET_IDS $warn_msg_suffix"
    fi
}

# source_env_files()
source_env_files() {
    # shellcheck disable=SC2034
    local -n files="${1?$(fatal "\$1 $ERROR_ARG_REQUIRED")}"

    [[ ${!files@a} == *a* ]] || fatal "${!files} must be an indexed array."

    # shellcheck disable=SC2068
    for e in ${files[@]}; do
        if [ -n "$e" ]; then
            [ -f "$e" ] || fatal "$ERROR_FILE_NOT_FOUND: $e"
            info "Sourcing $e"
            # shellcheck source=../../deploy/butane/base/secrets-example.env
            . "$e"
        fi
    done

}

if [ "${__hack_env_vendor_sourced:-}" != "true" ]; then
    declare __hack_env_vendor="hack/env/vendor.env"
    [ -f "$__hack_env_vendor" ] || { printf '%s\n' "failed to find file: $__hack_env_vendor" >&2; exit 1; }
    # shellcheck source=../env/vendor.env
    . "$__hack_env_vendor"
    unset __hack_env_vendor
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
