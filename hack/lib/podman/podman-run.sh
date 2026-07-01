# shellcheck shell=bash

declare -r __lib_podman_run_sourced="true"

podman_run() {
    debug "Starting ${FUNCNAME[0]}()"
    podman run "$@"
}

podman_run_env_wildcard_option_gen() {
    debug "Starting ${FUNCNAME[0]}()"
    local wildcard_prefix="${1?$(fatal "$ERROR_ARG_REQUIRED: \$1")}"

    # Remove * if one was already provided to prevent appending an extra * character
    printf "%s='%s*'" "--env" "${wildcard_prefix%\*}"
}

podman_run_opt_mount_bind_gen() {
    debug "Starting ${FUNCNAME[0]}()"
    local -r src="${1?$(fatal "$ERROR_ARG_REQUIRED: \$1")}"
    local -r target="${2?$(fatal "$ERROR_ARG_REQUIRED: \$2")}"

    printf '%s' "--volume=$src:$target:ro,z"
}

podman_run_opt_secret_mount_gen() {
    debug "Starting ${FUNCNAME[0]}()"
    local -r secret="${1?$(fatal "\$1 $ERROR_ARG_REQUIRED")}"
    shift

    local OPTIND=1
    local mode="" target="" uid="" gid=""
    while getopts ':m:t:u:g:' opt; do
        debug "-${opt} $OPTARG"
        case "$opt" in
            m) mode="$OPTARG" ;;
            t) target="$OPTARG" ;;
            u) uid="$OPTARG" ;;
            g) gid="$OPTARG" ;;
            :)
                fatal "-${OPTARG} $ERROR_OPTION_REQUIRED"
                return 1
                ;;
            ?)
                error "-${OPTARG} $ERROR_OPTION_UNKNOWN"
                return 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    [ -z "$target" ] && fatal "-t $ERROR_OPTION_REQUIRED"

    local out="$secret,target=$target"
    [ -n "$mode" ] && out+=",mode=$mode"
    [ -n "$uid" ]  && out+=",uid=$uid"
    [ -n "$gid" ]  && out+=",gid=$gid"

    printf -- "--secret=%s,type=mount" "$out"
}

if [ "${__lib_logging_sourced:-}" != "true" ]; then
    declare -r __lib_logging="hack/lib/logging.sh"
    [ -f "$__lib_logging" ] || { printf '%s\n' "failed to find file: $__lib_logging" >&2; exit 1; }
    # shellcheck source=../logging.sh
    . "$__lib_logging"
fi
