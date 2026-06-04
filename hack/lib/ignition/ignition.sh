#!/bin/bash

# declare -r __ignition_sourced="true"
declare -r __ignition_sourced="true"

# ignition_gen()
#
# args)
#   * $1) butane config; string - butane configuration to process be processed via `butane` stdin
#       * butane is the actual butane config loaded into memory (i. e. Contents of example.bu)
#       * butane file paths cannot be provided here
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
    debug "butane_opts=${butane_opts[*]}"

    # All referenced files must be in/under the same directory as the butane file.
    BUTANE_VOLUME_MOUNT="./$(dirname "$input")"
    info "Generating ignition from file: $input"
    # shellcheck disable=SC2068
    butane ${butane_opts[@]} "$(basename "$input")" || fatal "ignition generation failed: $input"
}

# ignition_check()
#
# args:
#   * stdin) butane config; string - butane configuration to process be processed via `butane` stdin
ignition_check() {
    local -r input="$(cat)"
    [ -z "$input" ] && fatal "\$1 input $ERROR_STDIN_NULL"

    if ! butane -cs <<< "$input"; then
        fatal "ignition check failed."
    fi
}

# ignition_gen_config_merge_inlines()
#
# args:
#   * 1) butane_path - string; Path to the main butane configuration file.
#       * This butane config is expected to have the paths of other butane files under .ignition.config.merge[].inline
#       * These butane configs will be converted into ignition configs and updated.
#   * 2) out - nameref; nameref to a set but empty variable. The final ignition configuration will be written to out.
#   * 3) $3 - nameref; nameref to an array of podman secret IDs to be mounted during ignition generation.
#       * Optional. If not provided, no secrets will be mounted.
ignition_gen_config_merge_inlines() {
    local -r butane_path="${1?$(fatal "$ERROR_ARG_NOT_PROVIDED: \$1")}"
    local -n out="${2?$(fatal "$ERROR_ARG_NOT_PROVIDED: \$2")}"

    main_json="$(yq -o json -I 0 '... comments="" | . | select(. != null)' "$butane_path")"

    local -r path_array_merge='["ignition", "config", "merge"]'
    local -ri path_array_merge_len="$(jq --argjson p "$path_array_merge" 'getpath($p) | length' <<< "$main_json")"
    debug "path_array_merge_len=$path_array_merge_len"

    for ((i=0; i<"$path_array_merge_len"; i++)); do
        path_array_inline_index="$(jq --argjson idx "$i" '. += [$idx, "inline"]' <<< "$path_array_merge")"

        local config_inline_path
        if ! config_inline_path="$(jq -r \
                                    --argjson path "$path_array_merge" \
                                    --argjson idx "$i" \
                                    --argjson path_index "$path_array_inline_index" \
                                    'if getpath($path) | length > $idx then
                                        getpath($path_index)
                                    else
                                        "Index out of bounds" | halt_error(1)
                                    end' \
                            <<< "$main_json")"; then

            fatal "failed to get $path_array_inline_index"
        fi

        local ignition_config_inline=""
        debug "Generating ignition from $path_array_inline_index: $config_inline_path"
        if ! ignition_config_inline="$(ignition_gen "$config_inline_path" "${3:-}")"; then
            fatal "failed to generate ignition config from: $config_inline_path"
        fi

        debug "Updating value of $path_array_inline_index"
        if ! main_json="$(jq -r \
                                --argjson path "$path_array_merge" \
                                --argjson idx "$i" \
                                --argjson path_index "$path_array_inline_index" \
                                --arg new_value "$ignition_config_inline" \
                                -c \
                                'if getpath($path) | length > $idx then
                                    getpath($path_index) = $new_value
                                else
                                    "Index out of bounds" | halt_error(1)
                                end' \
                    <<< "$main_json")"; then

            fatal "failed to update $path_array_inline_index"
        fi
    done

    info "Checking final main_json integrity..."
    ignition_check <<< "$main_json" || fatal && info "main_json ok"

    # shellcheck disable=SC2034
    out="$main_json"
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
