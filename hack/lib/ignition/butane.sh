#!/bin/bash
# tools to be used for processing ignition files
# should only be used by scripts in hack/ignition/lib

# declare -r __ignition_butane_sourced="true"
declare -r __ignition_butane_sourced="true"

# gather_butane_files()
# 
# Args:
# 1) main_bu - string; Butane file to parse for configs
# 2) files - nameref; Empty array, populated with butane config files
gather_butane_files() {
    local -r main_bu="$1"
    local -n files="$2"
    info "starting"

    local raw_butane_files
    # TODO simplify conversion into array by using yq output formatting options
    raw_butane_files="$(yq -e=1 '.ignition.config.merge[]' "$main_bu")"
    
    # remove local_ prefix
    local -r sed_opt_strip_local_prefix='s/inline_//'
    # convert : to _
    local -r sed_opt_trim_colon='s/: /_/g'
    local -r sed_val_opts="${sed_opt_trim_colon};${sed_opt_strip_local_prefix}"
    
    # Get files in full path format
    sed_out="$(sed "${sed_val_opts}" <<< "${raw_butane_files[*]}")"

    # shellcheck disable=SC2034
    mapfile -t files <<< "${sed_out}"
}

# gen_butane_main()
#
# args:
# * butane_main="$1" - string
#     - Main butane file path.
#     - .ignition.config.merge.[]
#         + Each item contains a path to a butane file.
#         + This butane file path is replaced with the generated ignition contents.
#         + Required as butane does not recursively generate configs for you.
#
# * ignitions_merge="$2" - nameref, array
#     - Each element contains the configuration to be merged.
#     - Order must match .ignition.config.merge.[]
#     - TODO investigate converting this into an associative array. The element order most likely does not match.
#         + This shouldn't be a problem, so long as the array lengths are the same.
#
# * butane_out="$3" - nameref, empty
#     - Declared empty variable used to return the final butane configuration.
#     - String holding the config in memory. Not a written file.
gen_butane_main() {
    local -r butane_main="$1"
    local -n ignitions_merge="$2"
    local -n butane_out="$3"
    info "Generating main ignition file."

    validate_config_dest_length "$2" "$butane_main"
    tmp_butane="$(yq "$butane_main")"

    # shellcheck disable=SC2068
    for i in ${!ignitions_merge[@]}; do
        merge_ignition="${ignitions_merge[$i]}"

        export YQ_pathEnv=".ignition.config.merge[$i].inline"
        export YQ_valueEnv="$merge_ignition"

        tmp_butane="$(yq -e=1 'eval(strenv(YQ_pathEnv)) = strenv(YQ_valueEnv)' <<< "$tmp_butane")"
    done

    info "Checking merged butane config."
    butane --check \
            --strict \
            <<< "$tmp_butane"

    # shellcheck disable=SC2034
    butane_out="$tmp_butane"
}

# write_butane()
# args
# 1) $1 - string; butane file path
# 2) butane_contents - nameref; final butane file contents
# 3) out - nameref; empty, for returning the tmp file path
write_butane() {
    local -n butane_contents="$2"
    local -n out="$3"

    out="$(mktemp -p deploy/butane -d --suffix=.tmp -t ".main_butane.XXX")"
    out="$out/main.bu"
    echo "$butane_contents" > "$out" || fatal "Failed to write butane_contents"

    TEMP_DATA+=("$out")
    TEMP_DATA+=("$(dirname "$out")")
}

# validate_config_dest_length()
# Compares an array to an integer, aborts if they aren't equal
#
# args
#    * 1) configs - array
#    * 2) butane_config - butane (yaml) file path
validate_config_dest_length() {
    local -n configs="$1"
    local -r butane_config="$2"

    local -i butane_config_merge_len
    butane_config_merge_len="$(yq '(.ignition.config.merge | length)' "$butane_config")"

    [ "${#configs[@]}" -ne "$butane_config_merge_len" ] \
        && error "configs length: ${#configs[@]} != ${butane_config_merge_len}"
}
