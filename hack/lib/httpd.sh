# shellcheck shell=bash

# declare -r __hack_lib_http_sourced="true"
declare -r __hack_lib_httpd_sourced="true"

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

        # local -r log_level="${PODMAN_LOG_LEVEL:-warn}"
        # 
        # Useful for debugging podman runtime errors
        local -r log_level="${PODMAN_LOG_LEVEL:-warn}"

        # local -r image="registry.access.redhat.com/hi/httpd:latest"
        local -r image="registry.access.redhat.com/hi/httpd:latest"

        podman run \
                --rm \
                -i \
                --name="httpd-ignition" \
                --publish=8080:8080 \
                --env 'HTTPD_*' \
                --log-level="$log_level" \
                --volume="$vol":/var/www/html:ro,Z \
                "$image"
}

# must export for scripts (or any subshell) to access it
export -f httpd
