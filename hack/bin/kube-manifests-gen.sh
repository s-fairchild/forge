#!/bin/bash

set -o nounset \
    -o errexit

DEBUG="${DEBUG:-"false"}"
if [ "$DEBUG" == "true" ]; then
    set -x
fi

# main()
#
# Entry point. Validates arguments and delegates to generate_kube_manifests.
#
# args:
#   * 1) base_dir  - string; root path to search for overlay directories.
#   * 2) manifests - string; destination directory for generated YAML files.
#   * 3) overlay   - string; overlay name to match (e.g. "prod", "staging").
main() {
    local -r base_dir="$1"
    local -r manifests="$2"
    local -r overlay="$3"

    mkdir -p "$base_dir" || fatal "unable to create $base_dir"
    mkdir -p "$manifests" || fatal "unable to create $manifests"

    generate_kube_manifests "$base_dir" \
                            "$manifests" \
                            "$overlay"
}

# generate_kube_manifests()
#
# Finds all directories named $overlay under $base, runs
# `kubectl kustomize --enable-helm` on each, and writes the output to
# $dest/<app-name>.yaml.  Apps listed in $disabled_pkgs are skipped.
#
# args:
#   * 1) base    - string; root path to search.
#   * 2) dest    - string; destination directory for generated YAML files.
#   * 3) overlay - string; directory name to match (e.g. "prod").
generate_kube_manifests() {
    local -r base="$1"
    local -r dest="$2"
    local -r overlay="$3"

    mapfile -t kustomize <<< "$(find "$base" -type d -name "$overlay")"

    # shellcheck disable=SC2068
    for k in ${kustomize[@]}; do
        app_name="$(get_app_name "$k")"
        app_manifest="$app_name.yaml"

        if is_enabled "$app_name" "$disabled_pkgs"; then
            kustomize_out="$dest/$app_manifest"

            info "Generating $app_manifest from $k"
            if kubectl kustomize \
                    --enable-helm=true \
                    "$k" > "$kustomize_out"; then
                info "Successfully created manifest file: $kustomize_out"
            fi
        fi
    done
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
    app="$(dirname "$1")"
    app="$(dirname "$app")"
    app="$(basename "$app")"

    echo "$app"
}

# is_enabled()
#
# Returns 0 if $app is NOT matched by the $disabled regex, non-zero if it is.
# Used to skip apps listed in $disabled_pkgs.
#
# args:
#   * 1) app      - string; application name to test.
#   * 2) disabled - string; ERE pattern of disabled app names (e.g. "(pihole|coredns-custom)").
is_enabled() {
    local -r app="$1"
    local -r disabled="$2"
    if [[ $app =~ ${disabled[*]} ]]; then
        info "$app is disabled."
        return 1
    fi

    return 0
}

if [ "${__lib_logging_sourced:-}" != "true" ]; then
    declare -r __lib_logging="hack/lib/logging.sh"
    [ -f "$__lib_logging" ] || { printf '%s\n' "Cannot source: $__lib_logging; file not found" >&2; exit 5; }
    # shellcheck source=../lib/logging.sh
    . "$__lib_logging"
fi

if [ "${__env_gen_kub_manifests_sourced:-}" != "true" ]; then
    declare -r __env_gen_kub_manifests="hack/env/kube-manifests-gen.env"
    [ -f "$__env_gen_kub_manifests" ] || fatal --status=5 "Cannot source: ${__env_gen_kub_manifests}; file not found."
    # shellcheck source=../env/kube-manifests-gen.env
    . "$__env_gen_kub_manifests"
fi

main "$@"
