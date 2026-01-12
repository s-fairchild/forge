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

    while getopts 'k' opt; do
        case "${opt}" in
            k)

                ;;
            *)
                command ...
                ;;
        esac
    done

    # shellcheck disable=SC2034
    local -a ignitions
    gen_merge_ignitions "$butane_main" ignitions
    log "Successfully generated ignition.config.merge contents."

    # shellcheck disable=SC2034
    local butane_merged
    gen_butane_main "$butane_main" \
                    ignitions \
                    butane_merged

    # shellcheck disable=SC2034
    # local ignition_final
    local -r ignition_final="$(gen_ignition butane_merged)"

    local ignition_final_output_file
    gen_file_name "$butane_main" \
                    ignition_final_output_file \
                    "$BUTANE_FILE_EXTENSION"

    output_file_contents ignition_final "$ignition_final_output_file"
    log "Successfully generated final ignition file: ${ignition_final_output_file}"
}

# shellcheck disable=SC2034
# cleanup directory passed to trap
declare -a TEMP_DATA

# ignition_lib="hack/ignition/lib/ignition.sh"
ignition_lib="hack/ignition/lib/ignition.sh"
[ -f "$ignition_lib" ] || "$(echo "$ignition_lib not found. Are you in the repository root?"; exit 1)"
# shellcheck source=lib/ignition.sh
. "$ignition_lib" 

main "$@"
