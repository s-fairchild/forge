#!/bin/bash

# declare -r __ignition_utils_sourced="true"
declare -r __ignition_utils_sourced="true"

# gen_config_name()
#
# args:
#  * 1) src_file - string
#      - The source butane config file used for generating the ignition config.
gen_config_name() {
    local -r f="$1"

    # shellcheck disable=SC2128
    funcname=$FUNCNAME
    debug "$funcname: starting"
    debug "$funcname: \$f=$f"

    [ -f "$f" ] || error "File does not exist: $f"

    basename "$(dirname "$f")-$(basename "${f%%.*}")"
}

# import_to_podman_volume()
import_to_podman_volume() {
    local -n contents="$1"
    local -r vol="$2"

    [ -z "$contents" ] && warn "contents is empty."

    podman_volume_create "$vol"

    create_in_memory_tar "$@" \
    | podman volume \
            import \
            "$vol" \
            -
}

# create_in_memory_tar()
create_in_memory_tar() {
    local -n f_contents="$1"
    local -r vol="$2"
    local -r f_name="$3"

    # shellcheck disable=SC2128
    funcname=$FUNCNAME
    debug "$funcname: starting"

    local -r tar_py="hack/lib/tar.py" 
    debug "$funcname: \$tar_py=$tar_py"
    debug "$funcname: \$vol=$vol"
    debug "$funcname: \$f_name=$f_name"

    [ -f "$tar_py" ] || fatal "python script not found: $tar_py"

    printf '%s' "$f_contents" | python3 "$tar_py" "${f_name}"
}

podman_volume_create() {
    local -r vol="$1"

    # shellcheck disable=SC2128
    funcname=$FUNCNAME
    debug "$funcname: starting"

    debug "$funcname: \$vol=$vol"

    if podman volume exists "$vol"; then
        warn "podman volume already exists $vol"
        warn "Deleting podman volume: $vol"
        podman volume rm "$vol"
    fi

    # Possible nice to have features here
    #   * populate label overlay
    #   * populate bootstrap with butane or ignition
    #   * accept array of labels to apply, expand them with --label prefixing each string
    podman volume \
            create \
            --ignore \
            --label project="$(basename "$PWD")" \
            "$vol" \
    || fatal "failed to create podman volume: $vol"
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
    butane_config_merge_len="$(yq_len .ignition.config.merge "$butane_config")"

    [ "${#configs[@]}" -ne "$butane_config_merge_len" ] || error "configs length: ${#configs[@]} != ${butane_config_merge_len}"
}
