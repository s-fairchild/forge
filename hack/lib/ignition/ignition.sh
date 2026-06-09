#!/bin/bash

# declare -r __ignition_sourced="true"
declare -r __ignition_sourced="true"

# ignition_gen()
#
# Compiles a single butane (.bu) file to ignition JSON by running
# quay.io/coreos/butane:release in a podman container.  The directory
# containing the .bu file is mounted as the container workdir so that
# local file references in the config (e.g. under a "files" sub-directory)
# resolve correctly.  Output is written to stdout.
#
# args:
#   * 1) butane_file - string; relative path to a .bu file (e.g. deploy/butane/base/root.bu).
#         The file's parent directory is mounted into the container; only files at the
#         same depth or below are reachable by butane's --files-dir resolution.
#   * 2) secret_ids  - nameref (optional); array of podman secret IDs to mount into the
#         butane container at $__BUTANE_WORKDIR/files/secrets/ before compilation.
ignition_gen() {
    local -r input="${1?$(fatal "\$1 input $ERROR_ARG_NOT_PROVIDED")}"
    # shellcheck disable=SC2034
    local -n secret_mount_ids="${2:-__empty_array}"

    local butane_opts=(
        "--strict"
        # Pretty output prevents grossly long lines
        # "--pretty"
        # TODO test out removing --raw and generating machineconfigs
        "--raw"
    )

    local -r files_dir="files"

    # shellcheck disable=SC2034
    local -a BUTANE_SECRET_MOUNTS=()
    if [ -v secret_mount_ids ]; then
        info "Generating butane container secret mount options."
        gen_secret_mount_opts BUTANE_SECRET_MOUNTS \
                            secret_mount_ids \
                            "$__BUTANE_WORKDIR/$files_dir/secrets"
    fi
    debug "$(declare -p BUTANE_SECRET_MOUNTS)"

    # Only search for local files at the same depth as the butane file path
    # This simplifies creating the local file references in each butane config file.
    butane_opts+=("--files-dir=$files_dir")

    # All referenced files must be in/under the same directory as the butane file.
    BUTANE_VOLUME_MOUNT="./$(dirname "$input")"
    info "Generating ignition from file: $input"
    # shellcheck disable=SC2068
    butane ${butane_opts[@]} "$(basename "$input")" || fatal "ignition generation failed: $input"
}

# ignition_check()
#
# Validates an ignition JSON document by passing it to butane --check --strict
# (butane -cs) via stdin.  Aborts with fatal() on validation failure or empty input.
#
# args:
#   * stdin) ignition JSON string to validate.
ignition_check() {
    local -r input="$(cat)"
    [ -z "$input" ] && fatal "\$1 input $ERROR_STDIN_NULL"

    if ! butane -cs <<< "$input"; then
        fatal "ignition check failed."
    fi
}

# ignition_gen_config_merge_inlines()
#
# Reads the top-level butane config at butane_path, iterates every subordinate .bu
# file path listed under .ignition.config.merge[].inline, compiles each with
# ignition_gen(), replaces the inline path string with the resulting ignition JSON,
# then validates the fully merged document with ignition_check() before returning it.
#
# args:
#   * 1) butane_path - string; path to the top-level butane config (e.g. main.bu).
#         Must contain an .ignition.config.merge[] array whose entries each have an
#         "inline" field holding a relative path to a subordinate .bu file.
#   * 2) out         - nameref; receives the final merged ignition JSON string on success.
#   * 3) secret_ids  - nameref (optional); array of podman secret IDs passed through to
#         ignition_gen() for mounting secrets inside the butane container.
ignition_gen_config_merge_inlines() {
    local -r butane_path="${1?$(fatal "$ERROR_ARG_NOT_PROVIDED: \$1")}"
    local -n out="${2?$(fatal "$ERROR_ARG_NOT_PROVIDED: \$2")}"

    # Parse the top-level butane YAML to compact JSON, stripping all comments.
    local config_json
    config_json="$(yq -o json -I 0 '... comments="" | . | select(. != null)' "$butane_path")"

    # jq path array addressing .ignition.config.merge[].
    local -r merge_jq_path='["ignition", "config", "merge"]'

    local -ri entry_count="$(jq --argjson merge_jq_path "$merge_jq_path" \
                                'getpath($merge_jq_path) | length' \
                                <<< "$config_json")"
    debug "merge entry count: $entry_count"

    # jq function shared by both per-entry calls.
    # bounds_check(expr) guards against an out-of-range $idx before evaluating expr.
    # shellcheck disable=SC2016
    local -r _jq_bounds_check='def bounds_check(expr):
        if (getpath($merge_jq_path) | length) > $idx then expr
        else "Index \($idx) out of bounds" | halt_error(1) end;'

    local -i idx
    local inline_jq_path butane_file_path ignition_json
    local -a jq_args
    for ((idx = 0; idx < entry_count; idx++)); do

        # Extend the merge path with the current index and the "inline" key.
        # e.g. ["ignition","config","merge",0,"inline"]
        inline_jq_path="$(jq -c --argjson idx "$idx" '. += [$idx, "inline"]' \
                            <<< "$merge_jq_path")"

        # Args shared by both jq calls in this iteration.
        jq_args=(
            --argjson merge_jq_path  "$merge_jq_path"
            --argjson idx            "$idx"
            --argjson inline_jq_path "$inline_jq_path"
        )

        # Read the subordinate .bu file path from this inline entry.
        if ! butane_file_path="$(jq -r "${jq_args[@]}" \
                "$_jq_bounds_check bounds_check(getpath(\$inline_jq_path))" \
                <<< "$config_json")"; then
            fatal "failed to read inline path at merge index $idx"
        fi
        debug "butane_file_path=$butane_file_path"

        # Compile the .bu file to ignition JSON.
        debug "Generating ignition [$idx]: $butane_file_path"
        if ! ignition_json="$(ignition_gen "$butane_file_path" "${3:-}")"; then
            fatal "failed to generate ignition config from: $butane_file_path"
        fi

        # Replace the inline path string with the compiled ignition JSON.
        debug "Updating inline entry [$idx]: $inline_jq_path"
        if ! config_json="$(jq -rc "${jq_args[@]}" \
                --rawfile new_value <(printf '%s' "$ignition_json") \
                "$_jq_bounds_check bounds_check(getpath(\$inline_jq_path) = \$new_value)" \
                <<< "$config_json")"; then
            fatal "failed to update inline entry at merge index $idx"
        fi
    done

    info "Checking final config integrity..."
    ignition_check <<< "$config_json" || fatal
    info "Config ok"

    local -r config_bytes="$(printf '%s' "$config_json" | wc -c)"
    info "Final ignition config size: $config_bytes bytes"

    # shellcheck disable=SC2034
    out="$config_json"
}

if [ "${__lib_opt_bash_utils_logging_sourced:-}" != "true" ]; then
    declare -r __lib_opt_bash_utils_logging="hack/lib/opt-bash-utils-logging.sh"
    [ -f "$__lib_opt_bash_utils_logging" ] || "$(echo "$ERROR_FILE_NOT_FOUND: $__lib_opt_bash_utils_logging"; exit 1)"

    # shellcheck source=../../lib/opt-bash-utils-logging.sh
    . "$__lib_opt_bash_utils_logging" || "$(echo "failed to source file: $__lib_opt_bash_utils_logging"; exit 1)"
fi

if [ "${__hack_lib_ignition_butane_sourced:-}" != "true" ]; then
    declare -r __hack_lib_ignition_butane="hack/lib/ignition/butane.sh"
    [ -f "$__hack_lib_ignition_butane" ] || fatal "$ERROR_FILE_NOT_FOUND: $__hack_lib_ignition_butane"

    # shellcheck source=butane.sh
    . "$__hack_lib_ignition_butane"
fi

if [ "${__lib_yq_sourced:-}" != "true" ]; then
    declare -r __lib_yq="hack/lib/yq.sh"
    [ -f "$__lib_yq" ] || fatal "$ERROR_FILE_NOT_FOUND: $__lib_yq"

    # shellcheck source=../yq.sh
    . "$__lib_yq" || fatal "$ERROR_FILE_SOURCE_FAILED"
fi
