#!/bin/bash

# gen_all_ignitions()
# args:
# 1) arr - nameref; array containing all butane files to be processed for merging into main config
# TODO rename this function
gen_all_ignitions() {
    local -n arr="$1"
    log "starting"

    # shellcheck disable=SC2068
    for i in ${!arr[@]}; do
        conf="${arr[$i]}"
        arr[i]="$(gen_ignition conf)"
    done
}

# gen_ignition()
# args:
# 1) $1 - string; butane file to process
gen_ignition() {
    local -n butane_in="$1"
    log "starting"

    # The relative directory ignition uses to find "content: local" files
    # Should be the base directory of the main butane file (deploy).
    files_dir="${butane_in%%/*}"

    log "Generating ignition from: ${butane_in}, files-dir: ${files_dir}"
    butane -srp --files-dir="$files_dir" "$butane_in"
}

# gen_merge_configs()
# args:
# 1) main_bu - string; Butane file to parse for configs
# 2) files - nameref; Empty array, populated with butane config files
gen_merge_ignitions() {
    log "starting"

    # shellcheck disable=SC2034
    gather_butane_files "$1" "$2"
    gen_all_ignitions "$2"
}

# declare -r shell_utils_lib="shell-utils/usr/local/lib/utils.sh"
declare -r shell_utils_lib="shell-utils/usr/local/lib/utils.sh"
[ -f "$shell_utils_lib" ] || "$(echo "$shell_utils_lib not found."; exit 1)"
# shellcheck source=../../../shell-utils/usr/local/lib/utils.sh
source "$shell_utils_lib"

# declare -r constants="hack/ignition/lib/constants.env"
declare -r constants="hack/ignition/lib/constants.env"
[ -f "$constants" ] || abort "$constants not found."
# shellcheck source=constants.env
. "$constants" 

# declare -r butane_lib="hack/ignition/lib/butane.sh"
declare -r butane_lib="hack/ignition/lib/butane.sh"
[ -f "$butane_lib" ] || abort "$butane_lib ${ERROR_SOURCE_SUFFIX}"
# shellcheck source=butane.sh
. "$butane_lib" 

# declare -r ignition_utils="hack/ignition/lib/utils.sh"
[ -n "${ignition_utils:-}" ] || declare -r ignition_utils="hack/ignition/lib/utils.sh"
[ -f "$ignition_utils" ] || abort "$ignition_utils ${ERROR_SOURCE_SUFFIX}"
# shellcheck source=utils.sh
. "$ignition_utils" 
