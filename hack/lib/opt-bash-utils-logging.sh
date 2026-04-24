# shellcheck shell=bash

declare -r __lib_opt_bash_utils_logging_sourced="true"

if ! declare -F REQUIRES_CMDS > /dev/null; then
    declare -r __bash_utils_util_base_lib="hack/opt/bash-utils/util/base.sh"

    [ -f "$__bash_utils_util_base_lib" ] || "$(echo "$__bash_utils_util_base_lib file not found."; exit 5)"
    # shellcheck source=../opt/bash-utils/util/base.sh
    . "$__bash_utils_util_base_lib"
fi

if ! declare -F config_load_all > /dev/null; then
    declare -r __bash_utils_util_config="hack/opt/bash-utils/util/config.sh"

    [ -f "$__bash_utils_util_config" ] || "$(echo "__bash_utils_util_config=${__bash_utils_util_config} file not found."; exit 5)"
    # shellcheck source=../opt/bash-utils/util/config.sh
    . "$__bash_utils_util_config"
fi

if ! declare -F log > /dev/null; then
    declare -r __bash_utils_util_logging_lib="hack/opt/bash-utils/util/logging.sh"

    [ -f "$__bash_utils_util_logging_lib" ] || "$(echo "$__bash_utils_util_logging_lib file not found."; exit 5)"
    # shellcheck source=../opt/bash-utils/util/logging.sh
    . "$__bash_utils_util_logging_lib"
fi

config_load_all BASE_CONFIG_DEFAULTS BASE_CLI_ARGS
