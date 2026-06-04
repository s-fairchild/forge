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

# yq()
#
# Calls the yq command from $PATH preventing unintended recursion calls.
#   * 'YQ_*' variables within scope are exported for use by yq.
#   * 'YQ_*' are unexported upon completion
yq() {
    local -r log_level="${PODMAN_LOG_LEVEL:-warn}"
    local -r image="docker.io/mikefarah/yq:4.53.2"
    # local -Ix "${!YQ_*}"

    podman run \
        --userns keep-id \
        --env 'YQ_*' \
        --log-level "$log_level" \
        -i \
        --rm \
        -v "${PWD}:/workdir":O \
        --workdir /workdir \
        "$image" \
            --exit-status=1 \
            "$@"
}

if [ "${__lib_opt_bash_utils_logging_sourced:-}" != "true" ]; then
    declare -r shell_utils_logging="hack/lib/opt-bash-utils-logging.sh"

    [ -f "$shell_utils_logging" ] || "$(echo "file not found: $shell_utils_logging"; exit 1)"
    # shellcheck source=opt-bash-utils-logging.sh
    . "$shell_utils_logging" || "$(echo "failed to source file: $shell_utils_logging"; exit 1)"
fi
