# shellcheck shell=bash

declare -r __hack_lib_yq_sourced="true"

# upsert_hash_value()
#
# Upserts the verification.hash field at `.ignition.config.merge.[0].verification.hash`
# inside a butane/ignition JSON file in-place using yq.
#
# args:
#   * 1) f       - string; path to the JSON file to edit.
#   * 2) YQ_VALUE - string; hash value to set.
upsert_hash_value() {
    local -r f="$1"
    local -rx YQ_VALUE="$2"

    [ -f "$f" ] || fatal "$f not found."

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
# Thin podman wrapper around docker.io/mikefarah/yq:4.53.2.
# Mounts the current working directory as /workdir inside the container and
# forwards all YQ_* environment variables so callers can pass values via the
# environment without shell quoting issues.
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

if [ "${__bash_utils_base_config_logging_sourced:-}" != "true" ]; then
    declare -r __bash_utils_base_config_logging="hack/vendor/bash-utils/lib/base-config-logging.sh"
    [ -f "$__bash_utils_base_config_logging" ] || { printf '%s\n' "failed to find file: $__bash_utils_base_config_logging" >&2; exit 1; }
    # shellcheck source=logging.sh
    . "$__bash_utils_base_config_logging"
fi
