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
    debug "Starting ${FUNCNAME[0]}()"
    local -r base="${1?$(fatal "\$1 $error_arg_required")}"
    local -r out="${2?$(fatal "\$2 $error_arg_required")}"
    local -r overlay="${3?$(fatal "\$3 $error_arg_required")}"
    debug "$(declare -p base)"
    debug "$(declare -p out)"
    debug "$(declare -p overlay)"

    mkdir -p "$base" || fatal "$ERROR_FAILED_TO_CREATE_DIR: $base"
    mkdir -p "$out" || fatal "$ERROR_FAILED_TO_CREATE_DIR: $out"

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
    debug "Starting ${FUNCNAME[0]}()"
    local -r app="${1?$(fatal "\$1 $error_arg_required")}"
    local -n enabled="${2?$(fatal "\$2 $error_arg_required")}"
    debug "$(declare -p app)"
    debug "$(declare -p enabled)"

    local enabled_regex
    enabled_regex="$(IFS='|'; printf '%s' "${enabled[*]}")"
    debug "$(declare -p enabled_regex)"
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
    local -r path="${1?$(fatal "\$1 $ERROR_ARG_REQUIRED")}"
    debug "Starting ${FUNCNAME[0]}()"

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
    debug "Starting ${FUNCNAME[0]}()"
    local -r pkgs="${1?$(fatal \$1 "$ERROR_ARG_REQUIRED")}"
    local -r dest="${2?$(fatal \$2 "$ERROR_ARG_REQUIRED")}"
    local -r overlay="${3?$(fatal \$3 "$ERROR_ARG_REQUIRED")}"
    debug "$(declare -p base)"
    debug "$(declare -p dest)"
    debug "$(declare -p overlay)"

    local -a MAPFILE=()
    mapfile -d '' -t < <(find "$pkgs" \
                              -type d \
                              -name "$overlay")
    debug "$(declare -p MAPFILE)"
    if [ ! -v MAPFILE ]; then
        error "No overlays were found in $pkgs."
        return 1
    fi

    local out app
    # shellcheck disable=SC2068
    for k in ${MAPFILE[@]}; do
        app="$(get_app_name "$k")"
        debug "$(declare -p app)"

        if is_enabled "$app" apps_enabled; then
            out="${dest}/${app}${__manifest_file_extension}"
            debug "$(declare -p out)"

            info "kustomize build $k"
            if ! kustomize build "$k" > "$out"; then
                error "kustomize build failed: $k"
                break 2
            fi
            info "$SYMBOL_SUCCEEDED Created: $out"
        fi
    done
}

if [ "${__hack_env_vendor_sourced:-}" != "true" ]; then
    declare __hack_env_vendor="hack/env/vendor.env"
    [ -f "$__hack_env_vendor" ] || { printf '%s\n' "failed to find file: $__hack_env_vendor" >&2; exit 1; }
    # shellcheck source=../env/vendor.env
    . "$__hack_env_vendor"
    unset __hack_env_vendor
fi

if [ "${__env_gen_kub_manifests_sourced:-}" != "true" ]; then
    declare -r __env_gen_kub_manifests="hack/env/kube-manifests-gen.env"
    [ -f "$__env_gen_kub_manifests" ] || fatal " $ERROR_FILE_NOT_FOUND: ${__env_gen_kub_manifests}"
    # shellcheck source=../env/kube-manifests-gen.env
    . "$__env_gen_kub_manifests"
fi

main "$@"
