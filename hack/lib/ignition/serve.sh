# hack/lib/ignition/serve.sh
#
# shellcheck shell=bash

[ "${XTRACE:-0}" -eq 1 ] && set -x

set -o nounset \
    -o errexit \
    -o pipefail \
    -o noclobber \
    -o hashall

declare -r __hack_lib_ignition_serve_sourced="true"

###############################
### Configuration Constants ###
###############################

# declare -r HTTPD_DROPINS_CONFIG_DEFAULT="hack/etc/httpd/ignition-secure.conf"
#
declare -r HTTPD_DROPINS_CONFIG_DEFAULT="hack/etc/httpd/ignition-secure.conf"

# declare -r NGINX_DROPINS_CONFIG_DEFAULT="hack/etc/nginx/ignition-secure.conf"
#
declare -r NGINX_DROPINS_CONFIG_DEFAULT="hack/etc/nginx/ignition-secure.conf"

# declare -r NGINX_IMAGE_NAME="nginx"
#
declare -r NGINX_IMAGE_NAME="nginx"

# declare -r HTTPD_IMAGE_NAME="httpd"
#
declare -r HTTPD_IMAGE_NAME="httpd"

declare -r __httpd_dropins_target="/etc/${HTTPD_IMAGE_NAME}/conf.d"
declare -r __nginx_dropins_target="/etc/${NGINX_IMAGE_NAME}/conf.d"

declare -r __httpd_serve_root="/usr/share/${HTTPD_IMAGE_NAME}/html"
declare -r __nginx_serve_root="/usr/share/${NGINX_IMAGE_NAME}/html"

# declare -r HTTPD_ENV_PREFIX_WILDCARD="${HTTPD_IMAGE_NAME^^}_*"
#
declare -r HTTPD_ENV_PREFIX_WILDCARD="${HTTPD_IMAGE_NAME^^}_*"

# declare -r NGINX_ENV_PREFIX_WILDCARD="${NGINX_IMAGE_NAME^^}_*"
#
declare -r NGINX_ENV_PREFIX_WILDCARD="${NGINX_IMAGE_NAME^^}_*"

# declare -r SERVE_DEFAULT_PUBLISH_PORT="8080/tcp"
#
declare -r SERVE_DEFAULT_PUBLISH_PORT="8080/tcp"

# declare -Ar SERVER_IMAGES=(
#    # httpd source reference: https://images.redhat.com/?name=httpd&version=latest
#    ["httpd"]="registry.access.redhat.com/hi/$HTTPD_IMAGE_NAME:latest"
#
#    # https://images.redhat.com/?name=nginx&version=latest
#    ["nginx"]="registry.access.redhat.com/hi/$NGINX_IMAGE_NAME:latest"
# )
declare -Ar SERVER_IMAGES=(
    # httpd source reference: https://images.redhat.com/?name=httpd&version=latest
    ["httpd"]="registry.access.redhat.com/hi/$HTTPD_IMAGE_NAME:latest"

    # https://images.redhat.com/?name=nginx&version=latest
    ["nginx"]="registry.access.redhat.com/hi/$NGINX_IMAGE_NAME:latest"
)

serve() {
    debug "Starting ${FUNCNAME[0]}()"
    debug "$*"

    local -a secrets=() dropins=() env_suffixes=()
    local opt image="" publish="$SERVE_DEFAULT_PUBLISH_PORT" regex
    while getopts ':s:d:e:i:p:' opt; do
        debug "-${opt} $OPTARG"
        case "$opt" in
            s)
                debug "Appending to secrets: $OPTARG"
                secrets+=("$OPTARG")
                ;;
            d)
                debug "Appending to dropins: $OPTARG"
                dropins+=("$OPTARG")
                ;;
            e)
                debug "Appending to env_suffixes: $OPTARG"
                env_suffixes+=("$OPTARG")
                ;;
            i)
                regex="$(IFS='|'; echo "${!SERVER_IMAGES[*]}")"
                debug "$(declare -p regex)"
                [[ "$OPTARG" =~ $regex ]] || fatal "-$opt ${OPTARG} is not configured as a server image. Server images: ${!SERVER_IMAGES[*]}"
                debug "Setting image=$OPTARG"
                image="$OPTARG"
                ;;
            p)
                debug "Updating publish=$OPTARG"
                publish="$OPTARG"
                ;;
            :)
                error "-${OPTARG} $ERROR_OPTION_REQUIRED"
                return 1
                ;;
            ?)
                error "-${OPTARG} $ERROR_OPTION_UNKNOWN"
                return 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    debug "$(declare -p secrets)"
    debug "$(declare -p dropins)"
    debug "$(declare -p env_suffixes)"
    debug "$(declare -p publish)"
    [ -v secrets ] || fatal "at least one secret option must be provided to be served."

    local -a podman_run_options=(
        "--rm"
        "-i"
        "--pull=missing"
        "--log-level=${PODMAN_LOG_LEVEL:-warn}"
        "--publish=0.0.0.0:8080:8080"
        "--publish=0.0.0.0:8081:8081"
    )

    _warn_default_dropins_config() {
        debug "Starting ${FUNCNAME[0]}()"
        warn "No dropins configuration files were provided. Using default configuration file: ${1:-}"
    }

    local env_default_suffix dropins_target serve_root
    case "$image" in
        "$HTTPD_IMAGE_NAME")
            image="${SERVER_IMAGES["$HTTPD_IMAGE_NAME"]}"
            env_default_suffix="$HTTPD_ENV_PREFIX_WILDCARD"
            dropins_target="$__httpd_dropins_target"
            serve_root="$__httpd_serve_root"

            if [ ! -v dropins ]; then
                _warn_default_dropins_config "$HTTPD_DROPINS_CONFIG_DEFAULT"
                dropins+=("$HTTPD_DROPINS_CONFIG_DEFAULT")
            fi
            ;;
        "$NGINX_IMAGE_NAME")
            image="${SERVER_IMAGES["$NGINX_IMAGE_NAME"]}"
            env_default_suffix="$NGINX_ENV_PREFIX_WILDCARD"
            dropins_target="$__nginx_dropins_target"
            serve_root="$__nginx_serve_root"

            if [ ! -v dropins ]; then
                _warn_default_dropins_config "$NGINX_DROPINS_CONFIG_DEFAULT"
                dropins+=("$NGINX_DROPINS_CONFIG_DEFAULT")
            fi
            ;;
        *)
            fatal "image=\"$image\" not found in ${!SERVER_IMAGES[*]}"
            ;;
    esac
    debug "$(declare -p image)"

    # shellcheck disable=SC2068
    for d in ${dropins[@]}; do
        podman_run_options+=("$(podman_run_opt_mount_bind_gen "$d" "$dropins_target/$(basename "$d")")")
        debug "Appending dropin mount $d: $(declare -p podman_run_options)"
    done

    local -r regex=ssl
    # shellcheck disable=SC2068
    for s in ${secrets[@]}; do
        local -a secret_opts=()
        if [[ "$s" =~ $regex ]] && podman secret ls --filter="name=$regex*" -q &> /dev/null; then
            secret_opts+=("-t" "/run/secrets/$s" "-m" "0400" "-u" "65532" "-g" "65532")
        else
            secret_opts+=("-t" "$serve_root/$s" "-m" "0444")
        fi
        debug "$(declare -p secret_opts)"

        podman_run_options+=("$(podman_run_opt_secret_mount_gen "$s" "${secret_opts[@]}")")
        debug "Appending --secret=$s: $(declare -p podman_run_options)"
    done

    # shellcheck disable=SC2068
    for e in ${env_suffixes[@]} "$env_default_suffix"; do
        podman_run_options+=("$(podman_run_env_wildcard_option_gen "$e")")
        debug "Appending env suffix $e: $(declare -p podman_run_options)"
    done

    # shellcheck disable=SC2068
    podman_run ${podman_run_options[@]} \
        "$image" \
        "$@"
}

# serve_nginx()
serve_nginx() {
    debug "Starting ${FUNCNAME[0]}()"
    serve -i "$NGINX_IMAGE_NAME" "$@"
}

# serve_httpd()
serve_httpd() {
    debug "Starting ${FUNCNAME[0]}()"
    serve -i "$HTTPD_IMAGE_NAME" "$@"
}

if [ "${__lib_logging_sourced:-}" != "true" ]; then
    declare -r __lib_logging="hack/lib/logging.sh"
    [ -f "$__lib_logging" ] || { printf '%s\n' "failed to find file: $__lib_logging" >&2; exit 1; }
    # shellcheck source=../logging.sh
    . "$__lib_logging"
fi

if [ "${__lib_podman_sourced:-}" != "true" ]; then
    declare -r __lib_podman="hack/lib/podman/podman.sh"
    [ -f "$__lib_podman" ] || fatal "$ERROR_FILE_NOT_FOUND: $__lib_podman"
    # shellcheck source=../podman/podman.sh
    . "$__lib_podman"
fi
