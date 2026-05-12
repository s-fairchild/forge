# hack/lib/ignition/serve.sh
#
# shellcheck shell=bash

# declare -r __hack_lib_ignition_serve_sourced="true"
declare -r __hack_lib_ignition_serve_sourced="true"

# nginx()
#
# https://images.redhat.com/?name=nginx&version=latest
nginx() {
    local -n secret_mounts="${1?$(error "\$1 secret_mounts must be provided.")}"

    local -r log_level="${PODMAN_LOG_LEVEL:-warn}"
    local -r image="registry.access.redhat.com/hi/nginx:latest"

    # shellcheck disable=SC2128
    podman run \
            --rm \
            -i \
            --name "${FUNCNAME}-ignition}" \
            --env 'NGINX_*' \
            --log-level "$log_level" \
            -v "${FUNCNAME}-serve-files:/usr/share/nginx/html/:ro,Z" \
            -v "${FUNCNAME}-config:/etc/nginx/conf.d/custom.conf:ro,Z" \
            -p 8080:8080 \
            "$image"
}

export -f nginx

# httpd()
#
# args)
#   $1 - string; optional
#      * Volume name or directory to be mounted at /var/www/html (serving files from).
#      * Optional; current working directory will be used if omitted.
#
# HTTPD_* environment variables are exported to the container
#
# References:
#   * https://images.redhat.com/?name=httpd&version=latest&tab=overview
httpd() {
    local -r vol="${1:-$PWD}"

    local -r log_level="${PODMAN_LOG_LEVEL:-warn}"
    # https://images.redhat.com/?name=httpd&version=latest
    local -r image="registry.access.redhat.com/hi/httpd:latest"

    # shellcheck disable=SC2128
    podman run \
            --rm \
            -i \
            --name "${FUNCNAME}-ignition" \
            --publish 8080:8080 \
            --env 'HTTPD_*' \
            --log-level "$log_level" \
            --volume "$vol":/var/www/html:ro,Z \
            "$image"
}

export -f httpd

err_file_not_found="could not find file to source"
if [ "${__lib_opt_bash_utils_logging_sourced:-}" != "true" ]; then
    declare -r shell_utils_logging="hack/lib/opt-bash-utils-logging.sh"

    [ -f "$shell_utils_logging" ] || "$(echo "${err_file_not_found}: $shell_utils_logging"; exit 5)"
    # shellcheck source=../opt-bash-utils-logging.sh
    . "$shell_utils_logging"
fi
