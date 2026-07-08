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

declare -r __NGINX_DROPIN_CONFIGS_SRC="hack/etc/nginx"
declare -r __NGINX_DROPIN_CONFIG_DEFAULT_SRC="${__NGINX_DROPIN_CONFIGS_SRC}/default.conf"
declare -r __NGINX_DROPIN_CONFIG_SECURE_SRC="${__NGINX_DROPIN_CONFIGS_SRC}/ignition-secure.conf"
declare -r __nginx_dropin_target="/etc/nginx/conf.d"
declare -r __nginx_serve_root="/usr/share/nginx/html"
declare -r __nginx_ssl_root="/run/secrets"

usage_serve() {
    cat <<USAGE >&2
Usage: serve -i ignition_secret -c ssl_cert -k ssl_key [-s secret]... [-d dropin_file]... [-e env_prefix]... [-h] [arg...]

Launches a containerised nginx server for serving ignition configs over HTTPS.

Options:
    -i ignition_secret  Name of the podman secret containing the ignition config to serve
                        as config.ign. (required)
    -c ssl_cert         Name of the podman secret containing the TLS certificate. (required)
    -k ssl_key          Name of the podman secret containing the TLS private key. (required)
    -s secret           Additional podman secret spec passed verbatim to \`podman run --secret\`
                        (e.g. "mydata,target=/usr/share/nginx/html/secrets/mydata").
                        May be specified multiple times.
    -d dropin_file      Dropin config bind-mounted into /etc/nginx/conf.d/.
                        May be specified multiple times.
                        (default: hack/etc/nginx/default.conf and hack/etc/nginx/ignition-secure.conf)
    -e env_prefix       Host env var wildcard prefix to pass through (e.g. "NGINX_").
                        May be specified multiple times.
    -h                  Print this usage message and exit.

Remaining arguments are passed through to the nginx container.
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
    local opt OPTIND=1 ignition ssl_key ssl_cert
    while getopts ':i:s:d:e:h:c:k:' opt; do
        case "$opt" in
            i) ignition="${OPTARG}"; local -r ignition ;;
            s) secrets+=("$OPTARG") ;;
            d) dropins+=("$OPTARG") ;;
            e) env_prefixes+=("$OPTARG") ;;
            c) ssl_cert="${OPTARG}" ;;
            k) ssl_key="${OPTARG}" ;;
            h) usage_serve; exit 0 ;;
            :) usage_serve; fatal "${ERROR_OPTION_REQUIRED}: -${OPTARG}" ;;
            ?) usage_serve; fatal "${ERROR_OPTION_UNKNOWN}: -${OPTARG}" ;;
        esac
    done
    shift $((OPTIND - 1))
    [ -z "${ignition:-}" ] && { usage_serve; fatal "-b $ERROR_OPTION_REQUIRED"; }
    [ -z "${ssl_cert:-}" ] && { usage_serve; fatal "-c $ERROR_OPTION_REQUIRED"; }
    [ -z "${ssl_key:-}" ] && { usage_serve; fatal "-k $ERROR_OPTION_REQUIRED"; }
    (( ${#secrets[@]} )) || { warn "No -s option(s) provided. No secrets will be mounted."; }
    debug "$(declare -p ignition secrets dropins env_prefixes ssl_cert ssl_key)"

    local -r __ssl_cert_mount_path="${__nginx_ssl_root}/ssl-cert"
    local -r __ssl_key_mount_path="${__nginx_ssl_root}/ssl-key"
    local -a podman_run_options=(
        "--rm"
        "-i"
        "--pull=missing"
        "--security-opt=label=disable"
        "--log-level=${PODMAN_LOG_LEVEL:-warn}"
        "--publish=0.0.0.0:8080:8080"
        "--publish=0.0.0.0:8081:8081"
        # Set ignition file to be served as index root
        "--secret=${ignition},target=${__nginx_serve_root}/config.ign,mode=0444"
        "--secret=${ssl_cert},target=${__ssl_cert_mount_path},mode=0400,uid=65532,gid=65532"
        "--secret=${ssl_key},target=${__ssl_key_mount_path},mode=0400,uid=65532,gid=65532"
    )

    local item
    (( ${#dropins[@]} )) || dropins=("$__NGINX_DROPIN_CONFIG_DEFAULT_SRC" "$__NGINX_DROPIN_CONFIG_SECURE_SRC")
    for item in "${dropins[@]}"; do
        podman_run_options+=("--volume=./$item:$__nginx_dropin_target/$(basename "$item"):ro")
    done

    for item in "${secrets[@]}"; do
        podman_run_options+=("--secret=${item},target=${__nginx_serve_root}/secrets/${item}")
    done

    for item in "${env_prefixes[@]}"; do
        # Strip a trailing '*' so an already-globbed prefix does not become '**'.
        podman_run_options+=("--env=${item%\*}*")
    done
    debug "$(declare -p podman_run_options)"

    podman run \
           "${podman_run_options[@]}" \
           "$__NGINX_IMAGE" \
           "$@" || fatal
}

if [ "${__hack_env_vendor_sourced:-}" != "true" ]; then
    declare __hack_env_vendor="hack/env/vendor.env"
    [ -f "$__hack_env_vendor" ] || { printf '%s\n' "failed to find file: $__hack_env_vendor" >&2; exit 1; }
    # shellcheck source=../../env/vendor.env
    . "$__hack_env_vendor"
    unset __hack_env_vendor
fi
