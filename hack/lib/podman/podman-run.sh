# shellcheck shell=bash

declare -r __lib_podman_run_sourced="true"

podman_run() {
    debug "Starting ${FUNCNAME[0]}()"
    podman run "$@"
}

podman_run_secret_or_mount_option_gen() {
    debug "Starting ${FUNCNAME[0]}()"
    local -r src="${1?$(fatal "$ERROR_ARG_REQUIRED: \$1")}"
    local target="${2?$(fatal "$ERROR_ARG_REQUIRED: \$2")}"
    local subpath="${3:-}"

    if [ -z "$subpath" ]; then
        local -r subpath="$(basename "$target")"
        debug "Updated subpath=$subpath"
        local -r target="$(dirname "$target")"
        debug "Updated target=$target"
    fi

    if podman_secret_exists "$src"; then
        debug "Returning secret option."
        echo -n "--secret=$src,target=$target/$subpath,type=mount"
    elif podman_volume_exists "$src"; then
        debug "Returning volume mount option."
        echo -n "--mount=type=volume,src=$src,target=$target,subpath=$subpath,ro,chown=true"
    elif [ -f "$src" ]; then
        debug "Returning bind mount option."
        echo -n "--mount=type=bind,src=$src,target=$target/$subpath,bind-propagation=slave,no-dereference,ro=true"
    else
        error "$PODMAN_ERROR_SECRET_NOT_FOUND: $src"
        error "$PODMAN_ERROR_VOLUME_NOT_FOUND: $src"
        error "$ERROR_FILE_NOT_FOUND: $src"
        error "$src must be a either a podman secret, volume or local file."

        return 1
    fi
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
    local -r subpath="${3:-}"

    local out="--volume=$src:$target:ro,z"

    echo -n "$out"
}

podman_run_opt_secret_mount_gen() {
    debug "Starting ${FUNCNAME[0]}()"
    local -r secret="${1?$(fatal "\$1 $ERROR_ARG_REQUIRED")}"
    shift

    _debug_option() {
        local -r v="${1?$(fatal "$ERROR_ARG_REQUIRED: \$1")}"
        debug "Option $v set: $(declare -p "$v")"
    }
    _fatal_option_required() {
        local -r o="${1?$(fatal "$ERROR_ARG_REQUIRED: \$1")}"
        fatal "-${o} $ERROR_OPTION_REQUIRED"
    }

    local OPTIND=1
    local mode="" target="" uid="" gid=""
    while getopts ':m:t:u:g:' opt; do
        debug "-${opt} $OPTARG"
        case "$opt" in
            m)
                mode="$OPTARG"
                _debug_option mode
                ;;
            t)
                target="$OPTARG"
                _debug_option target
                ;;
            u)
                uid=$OPTARG
                _debug_option uid
                ;;
            g)
                gid=$OPTARG
                _debug_option gid
                ;;
            :)
                _fatal_option_required "-${OPTARG}"
                return 1
                ;;
            ?)
                error "-${OPTARG} $ERROR_OPTION_UNKNOWN"
                return 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    local out
    # Required
    [ -z "$secret" ] && fatal "\$1 $ERROR_STRING_EMPTY" || out+="$secret"
    [ -z "$target" ] && _fatal_option_required "-t" || out+=",target=$target"

    # Optional
    [ -n "$mode" ] && out+=",mode=$mode"
    [ -n "$uid" ] && out+=",uid=$uid"
    [ -n "$gid" ] && out+=",gid=$gid"
    _debug_option "$out"

    # TODO configure an additional function(s) to allow secret type env
    printf -- "--secret=%s,type=mount" "$out"
}

if [ "${__lib_logging_sourced:-}" != "true" ]; then
    declare -r __lib_logging="hack/lib/logging.sh"
    [ -f "$__lib_logging" ] || { printf '%s\n' "failed to find file: $__lib_logging" >&2; exit 1; }
    # shellcheck source=../logging.sh
    . "$__lib_logging"
fi
