# shellcheck shell=bash

# declare PODMAN_SECRET_AUTHFILE="authfile"
declare PODMAN_SECRET_AUTHFILE="authfile"

# skopeo()
skopeo() {
    check_authfile_secret_exists "$PODMAN_SECRET_AUTHFILE"

    podman run \
            --rm \
            -it \
            --privileged \
            --entrypoint=skopeo \
            --secret="$PODMAN_SECRET_AUTHFILE" \
            --volume="$HOME/.local/share/containers/storage:/var/lib/containers/storage" \
            ubi9/skopeo \
                "$@"
}

# skopeo_copy()
skopeo_copy() {
    skopeo copy --dest-authfile=/run/secrets/authfile "$1" "$2"
}

# check_authfile_secret_exists()
check_authfile_secret_exists() {
    podman secret exists "$1" || "$(echo "podman secret $1 not found. Exiting."; exit 1)"
}
