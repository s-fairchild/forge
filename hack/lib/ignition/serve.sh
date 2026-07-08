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

declare -r __NGINX_IMAGE_NAME="nginx"
# https://images.redhat.com/?name=nginx&version=latest
declare -r __NGINX_IMAGE="registry.access.redhat.com/hi/${__NGINX_IMAGE_NAME}:latest"
declare -r __NGINX_ENV_PREFIX_WILDCARD="${__NGINX_IMAGE_NAME^^}_*"

declare -r __NGINX_DROPINS_CONFIG_DEFAULT="hack/etc/${__NGINX_IMAGE_NAME}/ignition-secure.conf"
declare -r __nginx_dropins_target="/etc/${__NGINX_IMAGE_NAME}/conf.d"
declare -r __nginx_serve_root="/usr/share/${__NGINX_IMAGE_NAME}/html"

usage_serve() {
    cat <<USAGE >&2
Usage: serve -i image -s secret... [-h] [-d dropin_file]... [-e env_prefix]... [arg...]

Launches a containerized httpd or nginx server for serving ignition configs.

Options:
    -s secret       podman secret spec passed verbatim to \`podman run --secret\`
                    (e.g. "prod-ignition,target=/usr/share/httpd/html/config.ign,mode=0444").
                    May be specified multiple times; at least one is required.
    -d dropin_file  Dropin config bind-mounted into the server's conf.d.
                    May be specified multiple times.
                    (default: the image's *_DROPINS_CONFIG_DEFAULT)
    -e env_prefix   Host env var wildcard prefix to pass through (e.g. "HTTPD_").
                    May be specified multiple times. The image's default prefix is
                    always included.
    -h              print this usage message.

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
#   * -h          - print usage message.
#   * $@)         - trailing args are passed to the container.
serve() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    local -a secrets=() dropins=() env_prefixes=()
    local opt OPTIND=1
    while getopts ':s:d:e:h' opt; do
        case "$opt" in
            s)
                debug "Appending ${OPTARG} to secrets array."
                secrets+=("$OPTARG")
                ;;
            d)
                debug "Appending ${OPTARG} to dropins array."
                dropins+=("$OPTARG")
                ;;
            e)
                debug "Appending ${OPTARG} to env_prefixes array."
                env_prefixes+=("$OPTARG")
                ;;
            h)
                usage
                ;;
            :)
                usage_serve
                fatal "${ERROR_OPTION_REQUIRED}: -${OPTARG}"
                ;;
            ?)
                usage_serve
                fatal "${ERROR_OPTION_UNKNOWN}: -${OPTARG}"
                ;;
        esac
    done
    shift $((OPTIND - 1))
    debug "$(declare -p secrets dropins env_prefixes)"

    (( ${#secrets[@]} )) || { usage_serve; fatal "at least one -s secret must be provided."; }

    local -a podman_run_options=(
        "--rm"
        "-i"
        "--pull=missing"
        "--security-opt=label=disable"
        "--log-level=${PODMAN_LOG_LEVEL:-warn}"
        "--publish=0.0.0.0:8080:8080"
        "--publish=0.0.0.0:8081:8081"
    )

    local dropins_target item
    dropins_target="$__nginx_dropins_target"

    (( ${#dropins[@]} )) || dropins=("$__NGINX_DROPINS_CONFIG_DEFAULT")
    for item in "${dropins[@]}"; do
        podman_run_options+=("--volume=./$item:$dropins_target/$(basename "$item"):ro")
    done

    for item in "${secrets[@]}"; do
        podman_run_options+=("--secret=$item")
    done

    for item in "${env_prefixes[@]}"; do
        # Strip a trailing '*' so an already-globbed prefix does not become '**'.
        podman_run_options+=("--env=${item%\*}*")
    done

    debug "$(declare -p podman_run_options)"
    podman run \
           "${podman_run_options[@]}" \
           "$__NGINX_IMAGE" \
           "$@"
}

if [ "${__hack_env_vendor_sourced:-}" != "true" ]; then
    declare __hack_env_vendor="hack/env/vendor.env"
    [ -f "$__hack_env_vendor" ] || { printf '%s\n' "failed to find file: $__hack_env_vendor" >&2; exit 1; }
    # shellcheck source=../../env/vendor.env
    . "$__hack_env_vendor"
    unset __hack_env_vendor
fi
