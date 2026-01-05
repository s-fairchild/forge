#!/bin/bash

set -o nounset \
    -o errexit

[ -n "${DEBUG:-}" ] && set -x

main () {
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

if [ "${__podman_build_multi_stage_sourced:-}" != "true" ]; then
    # declare -r __podman_build_multi_stage_path="hack/lib/podman/build/build_multi_stage.sh"
    declare -r __podman_build_multi_stage_path="hack/lib/podman/build/build_multi_stage.sh"
    [ -f "$__podman_build_multi_stage_path" ] || "$(echo "$__podman_build_multi_stage_path file not found."; exit 5)"

    # shellcheck source=../lib/podman/build/build_multi_stage.sh
    . "$__podman_build_multi_stage_path"
fi


main "$@"
