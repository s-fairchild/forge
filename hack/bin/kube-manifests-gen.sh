#!/bin/bash

set -o nounset \
    -o errexit

DEBUG="${DEBUG:-"false"}"
if [ "$DEBUG" == "true" ]; then
    set -x
fi

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

generate_kube_manifests() {
    local -r base="$1"
    local -r dest="$2"
    local -r overlay="$3"

    mapfile kustomize <<< "$(find "$base" -type d -name "$overlay")"

    # shellcheck disable=SC2068
    for k in ${kustomize[@]}; do
        app_name="$(get_app_name "$k")"
        app_manifest="$app_name.yaml"

        if is_disabled "$app_name" "$disabled_pkgs"; then
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

get_app_name() {
    app="$(dirname "$1")"
    app="$(dirname "$app")"
    app="$(basename "$app")"

    echo "$app"
}

is_disabled() {
    local -r app="$1"
    local -r disabled="$2"
    if [[ $app =~ ${disabled[*]} ]]; then
        info "$app is disabled."
        return 1
    fi

    return 0
}

if [ "${__lib_opt_bash_utils_logging_sourced:-}" != "true" ]; then
    declare -r __lib_opt_bash_utils_logging="hack/lib/opt-bash-utils-logging.sh"
    [ -f "$__lib_opt_bash_utils_logging" ] || eval "$(echo "Cannot source: $__lib_opt_bash_utils_logging; file not found"; exit 5)"

    # shellcheck source=../lib/opt-bash-utils-logging.sh
    . "$__lib_opt_bash_utils_logging"
fi

if [ "${__env_gen_kub_manifests_sourced:-}" != "true" ]; then
    # declare -r __env_gen_kub_manifests="hack/env/kube-manifests-gen.env"
    declare -r __env_gen_kub_manifests="hack/env/kube-manifests-gen.env"
    [ -f "$__env_gen_kub_manifests" ] || fatal --status=5 "Cannot source: ${__env_gen_kub_manifests}; file not found."

    # shellcheck source=../env/kube-manifests-gen.env
    . "$__env_gen_kub_manifests"
fi

main "$@"
