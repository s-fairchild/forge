#!/bin/bash

# create_output_dir()
#
# args:
# * local -n out_dir="$1"
#     - Set empty variable. Used to return the created directory.
# * local -r template="$2"
#     - template used as the prefix of the directory name.
# * local -r src_file_path="${3:-'.'}"
#     - **Optional**
#     - Base directory. The new directory will be created under the base.
#     - Defaults to the current working directory.
create_output_dir() {
    local -n out_dir="$1"
    local -r template="$2"
    local -r src_file_path="${3:-'.'}"
    log "starting"

    tmpdir_base="$(dirname "$src_file_path")"
    # shellcheck disable=SC2034
    out_dir="$(mktemp --directory --tmpdir="${tmpdir_base}" "${template}.XXXX")"
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
    local -n src_file="$1"
    local -n out="$2"
    local -r file_ext="${3:-}"
    log "starting"

    out="${src_file//\//-}"

    if [ -z "$file_ext" ]; then
        if [[ "$file_ext" =~ ^\\. ]]; then
            log "file_ext: $file_ext\nfile_ext must be prefixed with a period character: ."
            return 1
        fi

        prefix="${out%.*}"
        out="${prefix}${file_ext}"
    fi

    local out_prefix
    create_output_dir out_prefix \
                    "$out" \
                    "$src_file"
    log "Created output directory: $out_prefix"

    out="${out_prefix}/${out}"
    log "Full generated path: $out"
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
    local -n f="$1"
    local -r out_f="${2:-}"

    if [ -n "$out_f" ]; then
        log "Writing file to $out_f"
        echo "$f" > "$out_f"
    else
        echo "$f"
    fi
}
