# shellcheck shell=bash

# upsert_hash_value()
upsert_hash_value() {
    local -r f="$1"
    local -rx YQ_VALUE="$2"

    [ -f "$f" ] || abort "$f not found."

    local -rx YQ_KEY=".ignition.config.merge.[0].verification.hash"
    log "Editing $f in-place."
    log "upserting $f:$YQ_KEY:$YQ_VALUE"

    yq -P \
        -oj \
        -i \
        'eval(strenv(YQ_KEY)) |= strenv(YQ_VALUE)' \
        "$f"
}

# format_hash()
format_hash() {
    local f="$1"
    local -n out="$2"

    [ -f "$f" ] || abort "$f not found."

    local checksum
    parse_hash_extension "$f" checksum
    local type
    parse_hash_value "$f" type

    # Reference: https://coreos.github.io/butane/config-fcos-v1_5
    # shellcheck disable=SC2034
    out="$type-$checksum"
    log "created butane verification.hash: $out"
}

# parse_hash_extension()
parse_hash_extension() {
    local -n t="$2"

    # shellcheck disable=SC2034
    t="$(cut -d ' ' -f 1 < "$1")"
}

# parse_hash_value()
parse_hash_value() {
    local -n v="$2"

    # shellcheck disable=SC2034
    v="$(basename "$1")"
    v="${v##*.}"
}

# declare -r YQ_DEFAULT_PERSIST_VOLUME="yq-persist"
declare -r YQ_DEFAULT_PERSIST_VOLUME="yq-persist"

yq_persist() {
    local -n files="${1?'Files must be provided.'}"
    local -r vol="${2:-$YQ_DEFAULT_PERSIST_VOLUME}"

    # shellcheck disable=SC2068
    for f in ${files[@]}; do
        [ -f "$f" ] || error "File not found: $f"
    done

    podman volume \
            create \
            --ignore \
            "$vol"

    # shellcheck disable=SC2068
    for f in ${files[@]}; do
        change_dir="$(dirname "$f")"
        tar -cf - \
            -C "$change_dir" \
            "$(basename "$f")" \
        | podman volume \
                import \
                "$vol" -
    done
}

# yq()
#
# Calls the yq command from $PATH preventing unintended recursion calls.
#   * 'YQ_*' variables within scope are exported for use by yq.
#   * 'YQ_*' are unexported upon completion
yq() {
    local -r yq_vol="${1:-$YQ_DEFAULT_PERSIST_VOLUME}"
    # local -Ix "${!YQ_*}"

    local -r log_level="${PODMAN_LOG_LEVEL:-warn}"
    local -r image="docker.io/mikefarah/yq:4.53.2"

    podman run \
        --userns keep-id \
        --env 'YQ_*' \
        --log-level "$log_level" \
        -i \
        --rm \
        -v "$yq_vol:/persist:z" \
        --workdir /persist \
        "$image" \
            --exit-status=1 \
            "$@"
}

if [ "${shell_utils_lib:-}" != "true" ]; then
    declare -r shell_utils_logging="hack/lib/opt-bash-utils-logging.sh"

    [ -f "$shell_utils_lib" ] || "$(echo "$shell_utils_lib file not found."; exit 1)"
    # shellcheck source=opt-bash-utils-logging.sh
    source "$shell_utils_logging"
fi
