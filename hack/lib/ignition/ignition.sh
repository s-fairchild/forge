#!/bin/bash

declare -r __ignition_sourced="true"

[[ "$(declare -p __empty_array 2>/dev/null)" == "declare -a"* ]] || declare -ar __empty_array=()

# ignition_gen()
#
# Compiles a single butane (.bu) file to ignition JSON by running
# quay.io/coreos/butane:release in a podman container.  The directory
# containing the .bu file is mounted as the container workdir so that
# local file references in the config (e.g. under a "files" sub-directory)
# resolve correctly.  Output is written to stdout.
#
# args:
#   * 1) butane_file   - string; relative path to a .bu file (e.g. deploy/butane/base/root.bu).
#         The file's parent directory is mounted into the container; only files at the
#         same depth or below are reachable by butane's --files-dir resolution.
#   * 2) secret_names  - nameref (optional); array of podman secret names to mount into the
#         butane container at $__BUTANE_WORKDIR/files/secrets/<name>.
ignition_gen() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    local -r input="${1?$(fatal "\$1 input $ERROR_ARG_REQUIRED")}"
    # shellcheck disable=SC2034
    local -n _secret_names_ref="${2:-__empty_array}"

    local -r files_dir="files"
    if [ -v _secret_names_ref ]; then
        local s
        for s in "${_secret_names_ref[@]}"; do
            butane_secret_opts+=("-s" "$s,type=mount,target=$__BUTANE_WORKDIR/$files_dir/secrets/$s")
        done
    fi

    local -a butane_opts=(
        "--strict"
        "--files-dir=$files_dir"
    )

    info "Generating ignition from file: $input"
    # shellcheck disable=SC2068
    butane ${butane_secret_opts[@]} \
        -- \
        ${butane_opts[@]} \
        "$(basename "$input")" \
        || fatal "ignition generation failed for $input"
}

# ignition_merge_read_inline_path()
#
# Reads the "inline" field at .ignition.config.merge[idx] from config_json —
# the relative path to that merge entry's subordinate .bu file. Performs a
# bounds check on idx against merge_jq_path first, via the shared bounds_check
# jq def, halting with jq's halt_error if idx is out of range. Output is
# written to stdout.
#
# Validates an ignition JSON document by passing it to butane --check --strict
# (butane -cs) via stdin.  Aborts with fatal() on validation failure or empty input.
#
# args:
#   * 1) config_json     - string; the in-progress merged butane config as compact JSON.
#   * 2) merge_jq_path   - string; compact JSON array addressing .ignition.config.merge[]
#         (e.g. ["ignition","config","merge"]).
#   * 3) idx             - integer; index of the entry to read within the merge array.
#   * 4) jq_bounds_check - string; jq `def bounds_check(expr): ...;` snippet shared with
#         ignition_merge_write_entry()'s jq call.
ignition_merge_read_inline_path() {
    local -r config_json="${1?$(fatal "$ERROR_ARG_REQUIRED: \$1")}"
    local -r merge_jq_path="${2?$(fatal "$ERROR_ARG_REQUIRED: \$2")}"
    local -ri idx="${3?$(fatal "$ERROR_ARG_REQUIRED: \$3")}"
    local -r jq_bounds_check="${4?$(fatal "$ERROR_ARG_REQUIRED: \$4")}"

    # Extend the merge path with the current index and the "inline" key.
    # e.g. ["ignition","config","merge",0,"inline"]
    local inline_jq_path
    inline_jq_path="$(jq -c --argjson idx "$idx" '. += [$idx, "inline"]' \
                        <<< "$merge_jq_path")"

    jq -r --argjson merge_jq_path  "$merge_jq_path" \
          --argjson idx            "$idx" \
          --argjson inline_jq_path "$inline_jq_path" \
          "$jq_bounds_check bounds_check(getpath(\$inline_jq_path))" \
          <<< "$config_json"
}

# ignition_merge_compile_entry()
#
# Compiles butane_file_path to ignition JSON via ignition_gen(), then hashes
# the result with sha512sum_gen() and formats it as an Ignition
# verification.hash value via checksum_format_verification_hash_sha512().
# Sets BUTANE_VOLUME_MOUNT so ignition_gen() mounts the compiled file's own
# directory, since local file references must live alongside butane_file_path.
# Results are returned via nameref args (not stdout) so that a fatal() on
# failure terminates the caller's shell directly, rather than only the
# subshell a stdout-capturing caller would fork.
#
# args:
#   * 1) butane_file_path      - string; relative path to a .bu file.
#   * 2) ignition_json_out     - nameref; receives the compiled ignition JSON string.
#   * 3) verification_hash_out - nameref; receives the "sha512-<hex>" formatted hash of
#         ignition_json_out.
#   * 4) secret_names          - nameref name (optional, may be empty); array of podman
#         secret names passed through to ignition_gen() for mounting secrets inside the
#         butane container.
ignition_merge_compile_entry() {
    local -r butane_file_path="${1?$(fatal "$ERROR_ARG_REQUIRED: \$1")}"
    local -n ignition_json_out="${2?$(fatal "$ERROR_ARG_REQUIRED: \$3")}"
    local -n verification_hash_out="${3?$(fatal "$ERROR_ARG_REQUIRED: \$4")}"
    # This is assigned as a string to pass the nameref from the above scope without creating another nameref.
    # Preventing circular namerefs.
    local -r secrets="${4:-'empty_array'}"

    # All referenced files must be in/under the same directory as the butane file.
    local -r BUTANE_VOLUME_MOUNT="./$(dirname "$butane_file_path")"

    debug "Generating ignition: $butane_file_path"
    if ! ignition_json_out="$(ignition_gen "$butane_file_path" "$secrets")"; then
        fatal "failed to generate ignition config from: $butane_file_path"
    fi

    debug "Generating verification hash: $butane_file_path"
    # shellcheck disable=SC2034
    if ! verification_hash_out="$(sha512sum_gen <<< "$ignition_json_out" | checksum_format_verification_hash_sha512)"; then
        fatal "failed to generate verification hash for: $butane_file_path"
    fi
}

# ignition_merge_write_entry()
#
# Writes ignition_json into .ignition.config.merge[idx].inline and
# verification_hash into .ignition.config.merge[idx].verification.hash within
# config_json. Performs the same bounds check on idx as
# ignition_merge_read_inline_path(). Output is written to stdout.
#
# args:
#   * 1) config_json       - string; the in-progress merged butane config as compact JSON.
#   * 2) merge_jq_path     - string; compact JSON array addressing .ignition.config.merge[].
#   * 3) idx               - integer; index of the entry to update within the merge array.
#   * 4) jq_bounds_check   - string; jq `def bounds_check(expr): ...;` snippet shared with
#         ignition_merge_read_inline_path()'s jq call.
#   * 5) ignition_json     - string; compiled ignition JSON to inline at this entry.
#   * 6) verification_hash - string; "sha512-<hex>" formatted hash of ignition_json.
ignition_merge_write_entry() {
    local -r config_json="${1?$(fatal "$ERROR_ARG_REQUIRED: \$1")}"
    local -r merge_jq_path="${2?$(fatal "$ERROR_ARG_REQUIRED: \$2")}"
    local -ri idx="${3?$(fatal "$ERROR_ARG_REQUIRED: \$3")}"
    local -r jq_bounds_check="${4?$(fatal "$ERROR_ARG_REQUIRED: \$4")}"
    local -r ignition_json="${5?$(fatal "$ERROR_ARG_REQUIRED: \$5")}"
    local -r verification_hash="${6?$(fatal "$ERROR_ARG_REQUIRED: \$6")}"

    # Extend the merge path with the current index and the "inline" key,
    # and again with the "verification","hash" keys.
    # e.g. ["ignition","config","merge",0,"inline"]
    # e.g. ["ignition","config","merge",0,"verification","hash"]
    local inline_jq_path verification_hash_jq_path
    inline_jq_path="$(jq -c --argjson idx "$idx" '. += [$idx, "inline"]' \
                        <<< "$merge_jq_path")"
    verification_hash_jq_path="$(jq -c --argjson idx "$idx" '. += [$idx, "verification", "hash"]' \
                        <<< "$merge_jq_path")"

    debug "Updating inline entry [$idx]: $inline_jq_path"
    jq -rc --argjson merge_jq_path             "$merge_jq_path" \
           --argjson idx                       "$idx" \
           --argjson inline_jq_path            "$inline_jq_path" \
           --argjson verification_hash_jq_path "$verification_hash_jq_path" \
           --rawfile new_value <(printf '%s' "$ignition_json") \
           --arg verification_hash "$verification_hash" \
           "$jq_bounds_check bounds_check(getpath(\$inline_jq_path) = \$new_value | getpath(\$verification_hash_jq_path) = \$verification_hash)" \
           <<< "$config_json"
}

# ignition_gen_config_merge_inlines()
#
# Reads the top-level butane config at butane_path, then for every subordinate
# .bu file path listed under .ignition.config.merge[].inline: reads the path
# via ignition_merge_read_inline_path(), compiles and hashes it via
# ignition_merge_compile_entry(), and writes the resulting ignition JSON plus
# its verification.hash back into the config via ignition_merge_write_entry().
# The fully merged document is then validated with butane_check() before
# returning it.
#
# args:
#   * 1) butane_path  - string; path to the top-level butane config (e.g. main.bu).
#         Must contain an .ignition.config.merge[] array whose entries each have an
#         "inline" field holding a relative path to a subordinate .bu file.
#   * 2) out          - nameref; receives the final merged ignition JSON string on success.
#   * 3) secret       - nameref (optional); array of podman secret names passed through to
#         ignition_merge_compile_entry() (and from there to ignition_gen()) for mounting
#         secrets inside the butane container.
ignition_gen_config_merge_inlines() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    local -r butane_path="${1?$(fatal "$ERROR_ARG_REQUIRED: \$1")}"
    local -n out="${2?$(fatal "$ERROR_ARG_REQUIRED: \$2")}"
    local -r secrets="${3:-}"

    # Parse the top-level butane YAML to compact JSON, stripping all comments.
    local config_json
    config_json="$(yq -o json -I 0 '... comments="" | . | select(. != null)' "$butane_path")"

    # jq path array addressing .ignition.config.merge[].
    local -r merge_jq_path='["ignition", "config", "merge"]'

    local -ri entry_count="$(jq --argjson merge_jq_path "$merge_jq_path" \
                                'getpath($merge_jq_path) | length' \
                                <<< "$config_json")"
    debug "merge entry count: $entry_count"

    # jq function shared by every per-entry jq call below.
    # bounds_check(expr) guards against an out-of-range $idx before evaluating expr.
    # shellcheck disable=SC2016
    local -r _jq_bounds_check='def bounds_check(expr):
        if (getpath($merge_jq_path) | length) > $idx then expr
        else "Index \($idx) out of bounds" | halt_error(1) end;'

    local -i idx
    local butane_file_path ignition_json verification_hash
    for ((idx = 0; idx < entry_count; idx++)); do
        debug "Processing merge entry [$idx]"

        if ! butane_file_path="$(ignition_merge_read_inline_path "$config_json" "$merge_jq_path" "$idx" "$_jq_bounds_check")"; then
            fatal "failed to read inline path at merge index $idx"
        fi
        debug "butane_file_path=$butane_file_path"

        ignition_merge_compile_entry "$butane_file_path" \
                                    ignition_json \
                                    verification_hash \
                                    secrets

        if ! config_json="$(ignition_merge_write_entry "$config_json" \
                                                    "$merge_jq_path" \
                                                    "$idx" \
                                                    "$_jq_bounds_check" \
                                                    "$ignition_json" \
                                                    "$verification_hash")"; then
            fatal "failed to update inline entry at merge index $idx"
        fi
    done

    info "Checking final config integrity..."
    local BUTANE_VOLUME_MOUNT
    BUTANE_VOLUME_MOUNT="./$(dirname "$butane_path")"

    local ignition_out
    if ! ignition_out="$(butane -- --strict "--files-dir=$__BUTANE_FILES_DIR" <<< "$config_json")"; then
        fatal "failed to compile merged butane config to ignition JSON"
    fi
    info "Config ok"
    info "Config size: $(wc -c <<< "$ignition_out") bytes"

    # shellcheck disable=SC2034
    out="$ignition_out"
}

# get_secrets_from_env()
# TODO move this into hack/lib/podman/podman-secret.sh
get_secrets_from_env() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    local -n names="${1?$(fatal "\$1 $ERROR_ARG_REQUIRED")}"
    local -r config_env="${2:-}"

    [ -z "$config_env" ] && warn "config_env was not specified. label env= will be empty."
    [[ ${!names@a} == *a* ]] || fatal "${!names} must be an indexed array."

    local -r warn_msg_suffix="is unset or unpopulated. No files were processed."
    if [ -v SECRET_FILES ]; then
        debug "$(declare -p SECRET_FILES)"
        # TODO directly add the SECRET_IDS returned here.
        podman_secret_create_from_file -l "env=$config_env" SECRET_FILES
        local f
        # shellcheck disable=SC2068
        for f in ${SECRET_FILES[@]}; do
            names+=("$(basename "$f")")
        done
    else
        warn "SECRET_FILES $warn_msg_suffix"
    fi

    if [ -v SECRET_IDS ]; then
        # shellcheck disable=SC2068
        for id in ${SECRET_IDS[@]}; do
            if podman secret exists "$id" > /dev/null 2>&1; then
                info "Adding podman secret: $id"
                names+=("$(podman secret inspect -f '{{.Spec.Name}}' "$id")")
            else
                error "podman secret \"$id\" does not exist. Skipping."
            fi
        done
    else
        warn "SECRET_IDS $warn_msg_suffix"
    fi
}

# source_env_files()
source_env_files() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    # shellcheck disable=SC2034
    local -n files="${1?$(fatal "\$1 $ERROR_ARG_REQUIRED")}"

    [[ ${!files@a} == *a* ]] || fatal "${!files} must be an indexed array."

    # shellcheck disable=SC2068
    for e in ${files[@]}; do
        if [ -n "$e" ]; then
            [ -f "$e" ] || fatal "$ERROR_FILE_NOT_FOUND: $e"
            info "Sourcing $e"
            # shellcheck source=../../../deploy/butane/overlays/prod/secrets.env
            . "$e"
        fi
    done
}

if [ "${__bash_utils_base_config_logging_sourced:-}" != "true" ]; then
    declare -r __bash_utils_base_config_logging="hack/vendor/bash-utils/lib/base-config-logging.sh"
    [ -f "$__bash_utils_base_config_logging" ] || { printf '%s\n' "failed to find file: $__bash_utils_base_config_logging" >&2; exit 1; }
    # shellcheck source=../../vendor/bash-utils/lib/base-config-logging.sh
    . "$__bash_utils_base_config_logging"
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
    . "$__lib_yq"
fi

if [ "${__hack_lib_checksum_sha512sum_sourced:-}" != "true" ]; then
    declare -r __hack_lib_checksum="hack/lib/checksum/checksum.sh"
    [ -f "$__hack_lib_checksum" ] || fatal "$ERROR_FILE_NOT_FOUND: $__hack_lib_checksum"
    # shellcheck source=../checksum/checksum.sh
    . "$__hack_lib_checksum"
fi
