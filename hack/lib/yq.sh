# shellcheck shell=bash

declare -r __hack_lib_yq_sourced="true"

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
    local -r yq_vol="${YQ_PERSIST_VOLUME:-$YQ_DEFAULT_PERSIST_VOLUME}"
    info "Persisting files to podman volume: $yq_vol"
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
        -v "$PWD:/workdir":O \
        --workdir /workdir \
        "$image" \
            --exit-status=1 \
            "$@"
}

if [ "${__lib_opt_bash_utils_logging_sourced:-}" != "true" ]; then
    declare -r shell_utils_logging="hack/lib/opt-bash-utils-logging.sh"

    [ -f "$shell_utils_logging" ] || "$(echo "$shell_utils_logging file not found."; exit 1)"
    # shellcheck source=opt-bash-utils-logging.sh
    . "$shell_utils_logging"
fi
