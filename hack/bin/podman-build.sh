#!/bin/bash

set -o nounset \
    -o errexit

[ -n "${DEBUG:-}" ] && set -x

# main()
#
# Extracts the build context directory from the trailing positional argument,
# derives the image name as its basename, and delegates to
# podman_build_with_options() with any remaining caller-supplied options.
main () {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    # shellcheck disable=SC2034
    local -a options_podman_build=("$@")

    # TODO create a getopts function that gathers the following
    # Any other options not in the GETOPTS string should be added to options_podman_build
    #   * -i image
    #   * -d context_dir
    local build_context_dir
    build_context_get options_podman_build build_context_dir
    info "User provided options: ${options_podman_build[*]}"

    local -r build_image="$(basename "$build_context_dir")"

    podman_build_with_options options_podman_build \
                              "$build_image" \
                              "$build_context_dir"

    info "Complete."
}

if [ "${__hack_env_vendor_sourced:-}" != "true" ]; then
    declare __hack_env_vendor="hack/env/vendor.env"
    [ -f "$__hack_env_vendor" ] || { printf '%s\n' "failed to find file: $__hack_env_vendor" >&2; exit 1; }
    # shellcheck source=../env/vendor.env
    . "$__hack_env_vendor"
    unset __hack_env_vendor
fi

if [ "${__podman_build_multi_stage_sourced:-}" != "true" ]; then
    declare __podman_build_multi_stage_path="hack/lib/podman/build/build_multi_stage.sh"
    [ -f "$__podman_build_multi_stage_path" ] || fatal "$__podman_build_multi_stage_path file not found."
    # shellcheck source=../lib/podman/build/build_multi_stage.sh
    . "$__podman_build_multi_stage_path"
    unset __podman_build_multi_stage_path
fi

main "$@"
