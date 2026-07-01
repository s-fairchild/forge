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

declare -r HTTPD_DROPINS_CONFIG_DEFAULT="hack/etc/httpd/ignition-secure.conf"
declare -r NGINX_DROPINS_CONFIG_DEFAULT="hack/etc/nginx/ignition-secure.conf"

declare -r NGINX_IMAGE_NAME="nginx"
declare -r HTTPD_IMAGE_NAME="httpd"

declare -r __httpd_dropins_target="/etc/${HTTPD_IMAGE_NAME}/conf.d"
declare -r __nginx_dropins_target="/etc/${NGINX_IMAGE_NAME}/conf.d"

declare -r __httpd_serve_root="/usr/share/${HTTPD_IMAGE_NAME}/html"
declare -r __nginx_serve_root="/usr/share/${NGINX_IMAGE_NAME}/html"

declare -r HTTPD_ENV_PREFIX_WILDCARD="${HTTPD_IMAGE_NAME^^}_*"
declare -r NGINX_ENV_PREFIX_WILDCARD="${NGINX_IMAGE_NAME^^}_*"

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
    local opt image=""
    while getopts ':s:d:e:i:' opt; do
        debug "-${opt} $OPTARG"
        case "$opt" in
            s)
                secrets+=("$OPTARG")
                ;;
            d)
                dropins+=("$OPTARG")
                ;;
            e)
                env_suffixes+=("$OPTARG")
                ;;
            i)
                local image_regex
                image_regex="$(IFS='|'; printf '%s' "${!SERVER_IMAGES[*]}")"
                [[ "$OPTARG" =~ $image_regex ]] || fatal "-$opt ${OPTARG} is not a configured server image. Valid images: ${!SERVER_IMAGES[*]}"
                image="$OPTARG"
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
    (( ${#secrets[@]} )) || fatal "at least one -s secret must be provided."

    local -a podman_run_options=(
        "--rm"
        "-i"
        "--pull=missing"
        "--log-level=${PODMAN_LOG_LEVEL:-warn}"
        "--publish=0.0.0.0:8080:8080"
        "--publish=0.0.0.0:8081:8081"
    )

    local env_default_suffix dropins_target serve_root
    case "$image" in
        "$HTTPD_IMAGE_NAME")
            image="${SERVER_IMAGES["$HTTPD_IMAGE_NAME"]}"
            env_default_suffix="$HTTPD_ENV_PREFIX_WILDCARD"
            dropins_target="$__httpd_dropins_target"
            serve_root="$__httpd_serve_root"
            if (( ! ${#dropins[@]} )); then
                warn "No dropin configs provided. Using default: $HTTPD_DROPINS_CONFIG_DEFAULT"
                dropins+=("$HTTPD_DROPINS_CONFIG_DEFAULT")
            fi
            ;;
        "$NGINX_IMAGE_NAME")
            image="${SERVER_IMAGES["$NGINX_IMAGE_NAME"]}"
            env_default_suffix="$NGINX_ENV_PREFIX_WILDCARD"
            dropins_target="$__nginx_dropins_target"
            serve_root="$__nginx_serve_root"
            if (( ! ${#dropins[@]} )); then
                warn "No dropin configs provided. Using default: $NGINX_DROPINS_CONFIG_DEFAULT"
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
        debug "Appended dropin mount: $d"
    done

    local -r ssl_regex=ssl
    # shellcheck disable=SC2068
    for s in ${secrets[@]}; do
        local -a secret_opts=()
        if [[ "$s" =~ $ssl_regex ]] && podman secret ls --filter="name=$ssl_regex*" -q &> /dev/null; then
            secret_opts+=("-t" "/run/secrets/$s" "-m" "0400" "-u" "65532" "-g" "65532")
        else
            secret_opts+=("-t" "$serve_root/$s" "-m" "0444")
        fi
        debug "$(declare -p secret_opts)"
        podman_run_options+=("$(podman_run_opt_secret_mount_gen "$s" "${secret_opts[@]}")")
        debug "Appended secret mount: $s"
    done

    # shellcheck disable=SC2068
    for e in ${env_suffixes[@]} "$env_default_suffix"; do
        podman_run_options+=("$(podman_run_env_wildcard_option_gen "$e")")
        debug "Appended env wildcard: $e"
    done

    # shellcheck disable=SC2068
    podman_run ${podman_run_options[@]} \
        "$image" \
        "$@"
}

serve_nginx() {
    debug "Starting ${FUNCNAME[0]}()"
    serve -i "$NGINX_IMAGE_NAME" "$@"
}

serve_httpd() {
    debug "Starting ${FUNCNAME[0]}()"
    serve -i "$HTTPD_IMAGE_NAME" "$@"
}

if [ "${__bash_utils_base_config_logging_sourced:-}" != "true" ]; then
    declare -r __bash_utils_base_config_logging="hack/vendor/bash-utils/lib/base-config-logging.sh"
    [ -f "$__bash_utils_base_config_logging" ] || { printf '%s\n' "failed to find file: $__bash_utils_base_config_logging" >&2; exit 1; }
    # shellcheck source=../../vendor/bash-utils/lib/base-config-logging.sh
    . "$__bash_utils_base_config_logging"
fi

if [ "${__lib_podman_sourced:-}" != "true" ]; then
    declare -r __lib_podman="hack/lib/podman/podman.sh"
    [ -f "$__lib_podman" ] || fatal "$ERROR_FILE_NOT_FOUND: $__lib_podman"
    # shellcheck source=../podman/podman.sh
    . "$__lib_podman"
fi
