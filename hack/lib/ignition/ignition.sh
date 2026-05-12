#!/bin/bash

# declare -r __ignition_sourced="true"
declare -r __ignition_sourced="true"

# declare -r __fatal_err_msg_missing_butane="butane_path must be provided."
declare -r __fatal_err_msg_missing_butane="butane_path must be provided."

# gen_ignition()
#
# args)
#   * $1) butane config; string - butane configuration to process be processed via `butane` stdin
#       * butane is the actual butane config loaded into memory (i. e. Contents of example.bu)
#       * butane file paths cannot be provided here
gen_ignition() {
    butane_opts=(
        "--strict"
        # Pretty output prevents grossly long lines
        "--pretty"
        # TODO test out removing --raw and generating machineconfigs
        "--raw"
    )

    local input

    if [ -n "${1-}" ]; then
        local -r input="$1"
        info "Generating ignition from file: $input"

        # Only search for local files at the same depth as the butane file path
        # This simplifies creating the local file references in each butane config file.
        butane_opts+=("--files-dir=$(dirname "$input")/files")

        # shellcheck disable=SC2068
        butane ${butane_opts[@]} "$input" || fatal "failed to generate ignition"
    else
        local -r input="$(cat)"
        info "Generating ignition from stdin."

        # shellcheck disable=SC2068
        butane ${butane_opts[@]} <<< "$input" || fatal "failed to generate ignition"
    fi
}

# butane_check()
#
# args)
#   * $1) butane config; string - butane configuration to process be processed via `butane` stdin
butane_check() {
    local input

    if [ -n "${1-}" ]; then
        local -r input="$1"
        debug "Validating butane from stdin."
    else
        local -r input="$(cat)"
        debug "Validating butane from file: $input"
    fi

    # shellcheck disable=SC2128
    [ -z "$input" ] && fatal "$FUNCNAME: $__fatal_err_msg_missing_butane"

    # shellcheck disable=SC2128
    butane --check \
            --strict \
            "$input" \
    || error "$FUNCNAME: butane --check failed."
}

# gen_ign_config_merge_inlines()
#
gen_ign_config_merge_inlines() {
    local -ra butane_path="${1?$(fatal "$__fatal_err_msg_missing_butane")}"

    ign_json="$(yq -o json -I 0 '... comments="" | . | select(. != null)' "$butane_path")"
    debug "ign_json=$ign_json"

    # local -r butane_f="$(basename "${butane_path[0]}")"

    debug "Getting .ignition.config.merge length."

    local -ri ign_config_merge_len="$(jq '.ignition.config.merge | length' <<< "$ign_json")"
    debug "ign_config_merge_len=$ign_config_merge_len"

    for ((i=0; i<"$ign_config_merge_len"; i++)); do
        debug "Getting raw value: .ignition.config.merge[$i].inline"
        config_inline_path="$(jq -r \
                                --argjson idx "$i" \
                                'if .ignition.config.merge | length > $idx then
                                    .ignition.config.merge[$idx].inline
                                else
                                    "Index out of bounds" | halt_error(1)
                                end' \
                            <<< "$ign_json" \
                            || fatal "failed to get .ignition.config.merge[$i].inline")"

        tmp_config_inline="$(gen_ignition "$config_inline_path")"

        debug "Updating value of .ignition.config.merge[$i].inline"
        ign_json="$(jq -r \
                        --argjson idx "$i" \
                        --arg new_value "$tmp_config_inline" \
                        'if .ignition.config.merge | length > $idx then
                            .ignition.config.merge[$idx].inline = $new_value
                        else
                            "Index out of bounds" | halt_error(1)
                        end' \
                    <<< "$ign_json" \
                    || fatal "failed to update .ignition.config.merge[$i].inline")"
    done

    # printf '%s' "$ign_json"
    yq "$ign_json" | gen_ignition
}

# podman_secret_create_ignition()
#
podman_secret_create_ignition() {
    local -r butane_path="$1"
    local -n ign="$2"

    overlay_name="$(basename "$(dirname "${butane_path%%.*}")")"
    podman_secret_name="${overlay_name}-ignition"
    info "Creating podman secret: $podman_secret_name"

    yq -o yaml \
        '... comments=""' \
        <<< "$ign" \
    | gen_ignition \
    | podman secret \
            create \
            --replace "$podman_secret_name" \
            - \
    || fatal "failed to create podman secret: $podman_secret_name"
}
