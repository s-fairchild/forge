#!/bin/bash

# declare -r __ignition_sourced="true"
declare -r __ignition_sourced="true"

# gen_all_ignitions()
# args:
# 1) arr - nameref; array containing all butane files to be processed for merging into main config
# TODO rename this function
gen_all_ignitions() {
    local -n arr="$1"

    info "Generating all ignitions."

    # shellcheck disable=SC2068
    for i in ${!arr[@]}; do
        # shellcheck disable=SC2034
        conf="${arr[$i]}"
        arr[i]="$(gen_ignition conf)"
    done
}

# gen_ignition()
# args:
# 1) $1 - string; butane file to process
gen_ignition() {
    local -n butane_in="$1"

    butane_opts=(
        "--strict"
        "--pretty"
        "--raw"
    )

    if [ -f "$butane_in" ]; then
        # The relative directory ignition uses to find "content: local" files
        # Should be the base directory of the main butane file (deploy).
        files_dir="${butane_in%%/*}"
        butane_opts+=("--files-dir=$files_dir")

        info "Generating ignition from: ${butane_in}"
        debug "files-dir: ${files_dir}"
        # shellcheck disable=SC2068
        butane ${butane_opts[@]} "$butane_in"
    else
        # butane_opts+=("<<<")
        info "Generating ignition from stdin."
        # shellcheck disable=SC2068
        butane ${butane_opts[@]} <<< "$butane_in"
    fi
}

# gen_merge_configs()
# args:
# 1) main_bu - string; Butane file to parse for configs
# 2) files - nameref; Empty array, populated with butane config files
gen_merge_ignitions() {
    info "Generating merge ignitions."

    # shellcheck disable=SC2034
    gather_butane_files "$1" "$2"
    gen_all_ignitions "$2"
}
