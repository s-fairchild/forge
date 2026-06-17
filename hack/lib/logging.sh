# hack/lib/logging.sh
#
# shellcheck shell=bash disable=SC2034

declare -r __lib_logging_sourced="true"

declare -r PODMAN_ERROR_VOLUME_NOT_FOUND="podman volume not found"
declare -r PODMAN_ERROR_SECRET_NOT_FOUND="podman secret not found"

if [ "${__util_base_sourced:-}" != "true" ]; then
    declare __util_base="hack/vendor/bash-utils/util/base.sh"
    [ -f "$__util_base" ] || { printf '%s\n' "failed to find file: $__util_base" >&2; exit 1; }
    # shellcheck source=../vendor/bash-utils/util/base.sh
    . "$__util_base"
    unset __util_base
fi

if [ "${__util_config_sourced:-}" != "true" ]; then
    declare __util_config="hack/vendor/bash-utils/util/config.sh"
    [ -f "$__util_config" ] || { printf '%s\n' "failed to find file: $__util_config" >&2; exit 1; }
    # shellcheck source=../vendor/bash-utils/util/config.sh
    . "$__util_config"
    unset __util_config
fi

if [ "${__util_logging_sourced:-}" != "true" ]; then
    declare __util_logging="hack/vendor/bash-utils/util/logging.sh"
    [ -f "$__util_logging" ] || { printf '%s\n' "failed to find file: $__util_logging" >&2; exit 1; }
    # shellcheck source=../vendor/bash-utils/util/logging.sh
    . "$__util_logging"
    unset __util_logging
fi

config_load_all BASE_CONFIG_DEFAULTS BASE_CLI_ARGS
