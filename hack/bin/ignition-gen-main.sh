#!/bin/bash
# Recursively generate all ignition files

set -o nounset \
    -o errexit

DEBUG="${DEBUG:-"false"}"
if [ "$DEBUG" == "true" ]; then
    set -x
fi

main() {
    local -r butane_main="${1?'main butane file must be specified.'}"

    # shellcheck disable=SC2034
    local -a ignitions
    gen_merge_ignitions "$butane_main" ignitions \
        && info "Successfully generated ignition.config.merge contents."

    # shellcheck disable=SC2034
    local butane_merged
    gen_butane_main "$butane_main" \
                    ignitions \
                    butane_merged \
    && info "Successfully generated butane merge contents"

    config_name_base="$(gen_config_name "$butane_main")"
    volume_name="${config_name_base}-${BUTANE_FILE_EXTENSION}"
    filename="${volume_name}.${BUTANE_FILE_EXTENSION}"

    import_to_podman_volume butane_merged \
                     "$volume_name" \
                     "$filename"

    # shellcheck disable=SC2034
    # local ignition_final
    local -r ignition_final="$(gen_ignition butane_merged)"

    volume_name="${config_name_base}-${IGNITION_FILE_EXTENSION}"
    filename="${config_name_base}.${IGNITION_FILE_EXTENSION}"

    import_to_podman_volume ignition_final \
                     "$volume_name" \
                     "$filename"
}

if [ "${__ignition_common_lib_sourced:-}" != "true" ]; then
    # declare -r __ignition_common_lib="hack/lib/ignition/lib/common.env"
    declare -r __ignition_common_lib="hack/lib/ignition/common.env"
    [ -f "$__ignition_common_lib" ] || "$(echo "$__ignition_common_lib FATAL file not found."; exit 5)"

    # shellcheck source=../lib/ignition/common.env
    . "$__ignition_common_lib"
fi

main "$@"
