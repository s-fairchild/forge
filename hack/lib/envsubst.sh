# hack/lib/envsubst.sh
#
# TODO move this into bash-helpers repository
# shellcheck shell=bash

# args:
#   * $@) all arguments are passed to the container
envsubst() {
    local -r log_level="${PODMAN_LOG_LEVEL:-warn}"
    local -r image="docker.io/steve51516/envsubst:latest"

    podman_run_options=(
        --rm \
        -i \
        --log-level "$log_level" \
        --env 'ENVSUBST_*' \
    )

    if [ -v "${ENVSUBST_SECRET_MOUNTS[*]}" ]; then
        mapfile -O "${#podman_run_options[@]}" \
                podman_run_options \
                < <(printf -- "--secret %s,type=env\n" "${ENVSUBST_SECRET_MOUNTS[@]}") 
    fi

    # shellcheck disable=SC2068
    podman run \
        ${podman_run_options[@]} \
        "$image" \
            -no-digit \
            -no-unset \
            -no-empty \
            "$@"
}

# Allow Makefile and other programs access
export -f envsubst
