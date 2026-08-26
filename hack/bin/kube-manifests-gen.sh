#!/bin/bash

set -o nounset \
    -o errexit

[ "${DEBUG:=0}" -eq 1 ] && set -x

# main()
#
# Entry point. Validates arguments and delegates to generate_kube_manifests.
#
# args:
#   * 1) base_dir  - string; root path to search for overlay directories.
#   * 2) manifests - string; destination directory for generated YAML files.
#   * 3) overlay   - string; overlay name to match (e.g. "prod", "staging").
main() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    local -r base="${1?$(fatal "\$1 ${ERROR_OPERAND_REQUIRED}")}"
    local -r out="${2?$(fatal "\$2 ${ERROR_OPERAND_REQUIRED}")}"
    local -r overlay="${3?$(fatal "\$3 ${ERROR_OPERAND_REQUIRED}")}"
    debug "$(declare -p base)"
    debug "$(declare -p out)"
    debug "$(declare -p overlay)"

    mkdir -p "$base" || fatal "${ERROR_FAILED_TO_CREATE_DIR}: $base"
    mkdir -p "$out" || fatal "${ERROR_FAILED_TO_CREATE_DIR}: $out"

    if ! generate_kube_manifests "$base" \
                                 "$out" \
                                 "$overlay"; then
        fatal "failed to generate kube manifests."
    fi
}

# is_enabled()
#
# Returns 0 if $app is NOT matched by the $disabled regex, non-zero if it is.
# Used to skip apps listed in $apps_enabled.
#
# args:
#   * 1) app          - string; application name to test.
#   * 2) apps_enabled - string; ERE pattern of disabled app names (e.g. "(pihole|coredns-custom)").
is_enabled() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    local -r app="${1?$(fatal "\$1 ${ERROR_OPERAND_REQUIRED}")}"
    local -n enabled="${2?$(fatal "\$2 ${ERROR_OPERAND_REQUIRED}")}"

    local enabled_regex
    enabled_regex="$(IFS='|'; printf '%s' "${enabled[*]}")"
    debug "$(declare -p app enabled enabled_regex)"
    [[ $app =~ ${enabled_regex} ]] || return 1
}

# get_app_name()
#
# Extracts the application name from an overlay directory path by walking two
# dirname levels up and taking the basename.
# Example: pkg/workloads/jellyfin/overlays/prod → jellyfin
#
# args:
#   * 1) path - string; overlay directory path as returned by find.
get_app_name() {
    local -r path="${1?$(fatal "\$1 ${ERROR_OPERAND_REQUIRED}")}"
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    basename "$(dirname "$(dirname "$path")")"
}

# generate_kube_manifests()
#
# Finds all directories named $overlay under $base, runs
# `kubectl kustomize --enable-helm` on each, and writes the output to
# $dest/<app-name>.yaml.  Apps listed in $apps_enabled are skipped.
#
# args:
#   * 1) base    - string; root path to search.
#   * 2) dest    - string; destination directory for generated YAML files.
#   * 3) overlay - string; directory name to match (e.g. "prod").
generate_kube_manifests() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    require_operands 3 "$@" || return 1
    local -r pkgs="$1"
    local -r dest="$2"
    local -r overlay="$3"

    debug "$(declare -p base)"
    debug "$(declare -p dest)"
    debug "$(declare -p overlay)"

    local -a MAPFILE=()
    mapfile -d '' -t < <(find "$pkgs" \
                              -type d \
                              -name "$overlay")
    if [ ! -v MAPFILE ]; then
        error "No overlays were found in $pkgs."
        return 1
    fi
    debug "$(declare -p MAPFILE)"

    local out app
    # shellcheck disable=SC2068
    for k in ${MAPFILE[@]}; do
        app="$(get_app_name "$k")"
        debug "$(declare -p app)"

        if is_enabled "$app" apps_enabled; then
            out="${dest}/${app}${__manifest_file_extension}"
            debug "$(declare -p out)"

            info "Building $k"
            if ! kustomize build "$k" > "$out"; then
                error "kustomize build failed: $k"
                break 2
            fi
            info "Build succeeded: $out"
        fi
    done
}

if [ "${__bash_logger_adapter_sourced:-}" != "true" ]; then
    declare __bash_logger_adapter_path="hack/vendor/bash-logger-adapter/adapter.sh"
    [ -f "$__bash_logger_adapter_path" ] || { printf '%s\n' "failed to find file: $__bash_logger_adapter_sourced" >&2; exit 1; }
    # shellcheck source=../vendor/bash-logger-adapter/adapter.sh
    . "$__bash_logger_adapter_path"
    unset __bash_logger_adapter_path
fi

if [ "${__vendor_bashkit_local_lib_bashkit_options_operands_utils_sourced:-}" != "true" ]; then
    declare __vendor_bashkit_local_lib_bashkit_options_operands_utils="hack/vendor/bashkit/local/lib/bashkit/options-operands-utils.sh"
    [ -f "$__vendor_bashkit_local_lib_bashkit_options_operands_utils" ] || fatal "${ERROR_FILE_NOT_FOUND}: ${__vendor_bashkit_local_lib_bashkit_options_operands_utils}"
    # shellcheck source=../vendor/bashkit/local/lib/bashkit/options-operands-utils.sh
    . "$__vendor_bashkit_local_lib_bashkit_options_operands_utils"
    unset __vendor_bashkit_local_lib_bashkit_options_operands_utils
fi

if [ "${__hack_etc_kube_manifests_gen_sourced:-}" != "true" ]; then
    declare __hack_etc_kube_manifests_gen="hack/etc/kube-manifests-gen.env"
    [ -f "$__hack_etc_kube_manifests_gen" ] || fatal " ${ERROR_FILE_NOT_FOUND}: ${__hack_etc_kube_manifests_gen}"
    # shellcheck source=../etc/kube-manifests-gen.env
    . "$__hack_etc_kube_manifests_gen"
    unset __hack_etc_kube_manifests_gen
fi

main "$@"
