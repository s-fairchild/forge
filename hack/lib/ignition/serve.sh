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

usage_serve() {
    cat <<USAGE >&2
Usage: serve -i image -s secret... [-d dropin_file]... [-e env_prefix]... [arg...]

Launches a containerized httpd or nginx server for serving ignition configs.

Options:
    -i image        Server image key; one of: ${!SERVER_IMAGES[*]}. (required)
    -s secret       podman secret spec passed verbatim to \`podman run --secret\`
                    (e.g. "prod-ignition,target=/usr/share/httpd/html/config.ign,mode=0444").
                    May be specified multiple times; at least one is required.
    -d dropin_file  Dropin config bind-mounted into the server's conf.d.
                    May be specified multiple times.
                    (default: the image's *_DROPINS_CONFIG_DEFAULT)
    -e env_prefix   Host env var wildcard prefix to pass through (e.g. "HTTPD_").
                    May be specified multiple times. The image's default prefix is
                    always included.

Remaining arguments are passed through to the server container.
USAGE
}

# serve()
#
# Launches a containerized httpd or nginx server for serving ignition configs.
#
# Options:
#   * -s <spec>   - podman secret spec passed verbatim to `podman run --secret`
#                   (e.g. "prod-ignition,target=/usr/share/httpd/html/config.ign,mode=0444").
#                   Repeatable; at least one is required.
#   * -d <file>   - dropin config bind-mounted into the server's conf.d. Repeatable.
#                   Defaults to the image's *_DROPINS_CONFIG_DEFAULT when omitted.
#   * -e <prefix> - host env var wildcard prefix to pass through (e.g. "HTTPD_").
#                   Repeatable. The image's default prefix is always included.
#   * -i <image>  - server image key; one of the SERVER_IMAGES keys. Required.
#   * $@)         - trailing args are passed to the container.
serve() {
    debug "Starting ${FUNCNAME[0]}()"
    debug "$*"

    local -a secrets=() dropins=() env_prefixes=()
    local opt image="" OPTIND=1
    while getopts ':s:d:e:i:' opt; do
        case "$opt" in
            s) secrets+=("$OPTARG") ;;
            d) dropins+=("$OPTARG") ;;
            e) env_prefixes+=("$OPTARG") ;;
            i) image="$OPTARG" ;;
            :) usage_serve; fatal "-${OPTARG} $ERROR_OPTION_REQUIRED" ;;
            ?) usage_serve; fatal "-${OPTARG} $ERROR_OPTION_UNKNOWN" ;;
        esac
    done
    shift $((OPTIND - 1))

    (( ${#secrets[@]} )) || { usage_serve; fatal "at least one -s secret must be provided."; }
    [ -n "$image" ] || { usage_serve; fatal "-i image $ERROR_ARG_REQUIRED"; }
    [ -v 'SERVER_IMAGES[$image]' ] \
        || fatal "-i $image is not a configured server image. Valid images: ${!SERVER_IMAGES[*]}"

    local dropins_target env_default_prefix
    case "$image" in
        "$HTTPD_IMAGE_NAME")
            dropins_target="$__httpd_dropins_target"
            env_default_prefix="$HTTPD_ENV_PREFIX_WILDCARD"
            (( ${#dropins[@]} )) || dropins=("$HTTPD_DROPINS_CONFIG_DEFAULT")
            ;;
        "$NGINX_IMAGE_NAME")
            dropins_target="$__nginx_dropins_target"
            env_default_prefix="$NGINX_ENV_PREFIX_WILDCARD"
            (( ${#dropins[@]} )) || dropins=("$NGINX_DROPINS_CONFIG_DEFAULT")
            ;;
    esac

    local -a podman_run_options=(
        "--rm"
        "-i"
        "--pull=missing"
        "--log-level=${PODMAN_LOG_LEVEL:-warn}"
        "--publish=0.0.0.0:8080:8080"
        "--publish=0.0.0.0:8081:8081"
    )

    local item
    for item in "${dropins[@]}"; do
        podman_run_options+=("--volume=./$item:$dropins_target/$(basename "$item"):ro,z")
    done

    for item in "${secrets[@]}"; do
        podman_run_options+=("--secret=$item")
    done

    for item in "${env_prefixes[@]}" "$env_default_prefix"; do
        # Strip a trailing '*' so an already-globbed prefix does not become '**'.
        podman_run_options+=("--env=${item%\*}*")
    done

    debug "$(declare -p podman_run_options)"
    podman_run "${podman_run_options[@]}" "${SERVER_IMAGES[$image]}" "$@"
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
