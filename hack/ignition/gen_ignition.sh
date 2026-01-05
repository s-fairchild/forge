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
    gen_merge_ignitions "$butane_main" ignitions
    info "Successfully generated ignition.config.merge contents."

    # shellcheck disable=SC2034
    local butane_merged
    gen_butane_main "$butane_main" \
                    ignitions \
                    butane_merged

    local output_dir
    create_output_dir output_dir "$butane_main"

    local butane_merged_output_filename
    gen_file_name "$butane_main" butane_merged_output_filename
    butane_merged_path="$output_dir/$butane_merged_output_filename"
    output_file_contents butane_merged "$butane_merged_path"
    info "Main butane file generated (for reference): $butane_merged_path"

    # shellcheck disable=SC2034
    # local ignition_final
    local -r ignition_final="$(gen_ignition butane_merged)"

    local ignition_final_output_file
    gen_file_name "$butane_main" ignition_final_output_file "$IGNITION_FILE_EXTENSION"
    ignition_final_path="$output_dir/$ignition_final_output_file"
    output_file_contents ignition_final "$ignition_final_path"

    info "Main ignition file generated: $ignition_final_path"
    info "Complete."
}

if [ "${__ignition_common_lib_sourced:-false}" == "false" ]; then
    # declare -r __ignition_common_lib="hack/ignition/lib/common.env"
    declare -r __ignition_common_lib="hack/ignition/lib/common.env"
    [ -f "$__ignition_common_lib" ] || "$(echo "$__ignition_common_lib FATAL file not found."; exit 5)"

    # shellcheck source=lib/common.env
    . "$__ignition_common_lib"
fi

main "$@"
