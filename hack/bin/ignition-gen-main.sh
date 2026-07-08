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
Usage: ${0##*/} -b butane_main [-n secret_prefix] [-l label]... [-e secrets_env]... [-h]

Recursively compile a root butane config, merging its inline references,
and store the resulting ignition JSON as a podman secret.

Options:
    -b butane_main           Path to the root butane config to compile and merge. (required)
    -p secret_prefix         Prefix for name of the podman secret to store the generated ignition JSON
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
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    local -a labels=() secret_envs=()
    local secret_prefix="" butane_main="" opt 
    local -i OPTIND=1
    while getopts ':p:l:e:b:h' opt; do
        case "$opt" in
            h)
                usage
                exit 0
                ;;
            p)
                [ -z "$secret_prefix" ] || fatal_duplicate_option "$OPTARG"
                secret_prefix="${OPTARG}"
                ;;
            l)
                # -l is inserted as an index before $OPTARG to preserve spacing when passed to podman_secret_create_replace_from_stdin
                labels+=("-${opt}" "$OPTARG")
                ;;
            e)
                secret_envs+=("$OPTARG")
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
    debug "$(declare -p secret_prefix labels secret_envs butane_main)"
    [ -z "${butane_main:-}" ] && { usage; fatal "-b $ERROR_OPTION_REQUIRED"; }
    [ -z "${secret_prefix:-}" ] && { usage; fatal "-p $ERROR_OPTION_REQUIRED"; }

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
                                            "ignition-${secret_prefix}" \
                                            <<< "$ignition_main"
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
