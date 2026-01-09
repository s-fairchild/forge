#!/bin/bash

set -o nounset \
    -o errexit

main () {
    # shellcheck disable=SC2034
    local -a options_podman_build=("$@")

    local build_context_dir
    build_context_get options_podman_build build_context_dir

    local -r build_context_basename="$(basename "$build_context_dir")"
    podman_build_with_options options_podman_build "$build_context_basename" build_context_dir
}

# declare -r podman_build_lib="hack/lib/podman/build/build_multi_stage.sh"
declare -r podman_build_lib="hack/lib/podman/build/build_multi_stage.sh"
# declare -r shell_utils_lib="shell-utils/usr/local/lib/utils.sh"
declare -r shell_utils_lib="shell-utils/usr/local/lib/utils.sh"

# TODO move sourcing shell-utils into podman build library
[ -f "$shell_utils_lib" ] || "$(echo "$shell_utils_lib file not found."; exit 1)"
# shellcheck source=../../shell-utils/usr/local/lib/utils.sh
source "$shell_utils_lib"

if_debug_set_xtrace

[ -f "$podman_build_lib" ] || abort "$podman_build_lib file not found."
log "Sourcing $podman_build_lib"
# shellcheck source=../lib/podman/build/build_multi_stage.sh
source "$podman_build_lib"

main "$@"
