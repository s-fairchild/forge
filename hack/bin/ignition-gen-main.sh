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
Usage: ${0##*/} -b butane_main -s secret_suffix [-l label]... [-h]

Recursively compile a root butane config, merging its inline references,
and store the resulting ignition JSON as a podman secret named ignition-<secret_suffix>.

Options:
    -b butane_main   Path to the root butane config to compile and merge. (required)
    -s secret_suffix Suffix appended to "ignition-" to form the podman secret name
                     (e.g. -p prod stores the result as "ignition-prod"). (required)
    -l label         Additional "key=value" label to attach to secrets created
                     during generation. May be specified multiple times.
    -h               Print this help message and exit.
USAGE
}

fatal_duplicate_option() { fatal "-${1?$(fatal "\$1 $ERROR_ARG_REQUIRED")} can only be specified once."; }

main() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    local -a labels=()
    local secret_suffix butane_main opt 
    local -i OPTIND=1
    while getopts ':s:l:b:h' opt; do
        case "$opt" in
            s) secret_suffix="${OPTARG}"; local -r secret_suffix ;;
            # -l is inserted as an index before $OPTARG to preserve spacing when passed to podman_secret_create_replace_from_stdin
            l) labels+=("-${opt}" "$OPTARG"); ;;
            b) butane_main="${OPTARG}"; local -r butane_main; ;;
            h) usage; exit 0; ;;
            :) usage; fatal "-${OPTARG} $ERROR_OPTION_REQUIRED"; ;;
            ?) usage; fatal "-${OPTARG} $ERROR_OPTION_UNKNOWN"; ;;
        esac
    done
    shift $((OPTIND - 1))
    [ -z "${butane_main:-}" ] && { usage; fatal "-b $ERROR_OPTION_REQUIRED"; }
    [ -z "${secret_suffix:-}" ] && { usage; fatal "-s $ERROR_OPTION_REQUIRED"; }
    debug "$(declare -p secret_suffix labels butane_main)"

    [ -f "${butane_main}" ] || { usage; fatal "${ERROR_FILE_NOT_FOUND}: ${butane_main}"; }

    # TODO move this into it's own script in hack/bin once functions are moved into hack/lib/podman/podman-secret.sh
    # source_env_files secret_envs
    # unset secret_envs
    # # shellcheck disable=SC2034
    # local -a secrets=()
    # get_secrets_from_env secrets
    # local -r secrets
    # debug "$(declare -p secrets)"

    # shellcheck disable=SC2034
    local ignition_main
    ignition_gen_config_merge_inlines "$butane_main" \
                                    ignition_main

    labels+=("-l" "format=ignition")
    # shellcheck disable=SC2068
    podman_secret_create_replace_from_stdin ${labels[@]} \
                                            "ignition-${secret_suffix}" \
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
    declare podman_secrets="hack/lib/podman/podman-secret.sh"
    [ -f "$podman_secrets" ] || fatal "$ERROR_FILE_NOT_FOUND: $podman_secrets"
    # shellcheck source=../lib/podman/podman-secret.sh
    . "$podman_secrets"
    unset podman_secrets
fi

if [ "${__ignition_sourced:-}" != "true" ]; then
    declare ignition_lib="hack/lib/ignition/ignition.sh"
    [ -f "$ignition_lib" ] || fatal "$ERROR_FILE_NOT_FOUND: $ignition_lib"
    # shellcheck source=../lib/ignition/ignition.sh
    . "$ignition_lib"
    unset ignition_lib
fi

main "$@"
