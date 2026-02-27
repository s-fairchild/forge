#!/bin/bash

# declare -r __ignition_utils_sourced="true"
declare -r __ignition_utils_sourced="true"

# create_output_dir()
#
# args:
# * 1) local -n out_dir="$1"
#     - Set empty variable. Used to return the created directory.
# * 2) local -r src_file_path="${2:-'.'}"
#     - **Optional**
#     - Base directory. The new directory will be created under the base.
#     - Defaults to the current working directory.
create_output_dir() {
    local -n out_dir="$1"
    local -r src_file_path="${2:-'.'}"
    info "starting"

    tmpdir="$(dirname "$src_file_path")"
    [ -d "$tmpdir" ] || fatal "Base output directory not found: $tmpdir"

    tmpdir_ign="${tmpdir}/.ignitions"
    [ -d "$tmpdir_ign" ] || info "Creating directory: $tmpdir_ign"; mkdir -p "$tmpdir_ign"

    # shellcheck disable=SC2034
    out_dir="$(mktemp --directory --tmpdir="$tmpdir_ign" "$(basename "$0").XXXXXX")"
    info "Created output directory: $out_dir"
}

# gen_file_name()
#
# args:
#  * 1) src_file - string
#      - The source config file used for generating the output file.
#  * 2) out - nameref
#      - empty declared variable used to return the generated filename.
#  * 3) file_ext - string
#      - **Optional**
#      - Provide a file extension to use. Replaces the src_file extension if present.
gen_file_name() {
    local -r src_file="$1"
    local -n out="$2"
    local -r file_ext="${3:-}"
    info "starting"

    out="${src_file//\//-}"

    if [ -n "$file_ext" ]; then
        if [[ "$file_ext" =~ ^\\. ]]; then
            fatal "file_ext: $file_ext\nfile_ext must be prefixed with a period character: ."
        fi

        prefix="${out%.*}"
        out="${prefix}${file_ext}"
    fi

    info "Output filename generated: $out"
}

# output_file_contents()
# 
# args:
# * local -n f="$1"
#     - File contents.
# * local -r out_file="$2"
#     - **Optional**
#     - Output file path. Defaults to stdout.
output_file_contents() {
    local -n contents="$1"
    local -r out_f="${2:-}"

    if [ -n "$out_f" ]; then
        info "Writing file to $out_f"
        printf "%s\n" "$contents" > "$out_f"
    else
        printf "%s\n" "$contents"
    fi
}

if ! declare -F REQUIRES_CMDS > /dev/null; then
    # declare -r __bash_utils_util_base_lib="hack/opt/bash-utils/util/base.sh"
    declare -r __bash_utils_util_base_lib="hack/opt/bash-utils/util/base.sh"
    [ -f "$__bash_utils_util_base_lib" ] || "$(echo "$__bash_utils_util_base_lib FATAL file not found."; exit 5)"

    # shellcheck source=../../opt/bash-utils/util/base.sh
    . "$__bash_utils_util_base_lib"
fi

if ! declare -F log > /dev/null; then
    # declare -r __bash_utils_util_logging_lib="hack/opt/bash-utils/util/logging.sh"
    declare -r __bash_utils_util_logging_lib="hack/opt/bash-utils/util/logging.sh"
    [ -f "$__bash_utils_util_logging_lib" ] || "$(echo "$__bash_utils_util_logging_lib FATAL file not found."; exit 5)"

    # shellcheck source=../../opt/bash-utils/util/logging.sh
    . "$__bash_utils_util_logging_lib"
fi
