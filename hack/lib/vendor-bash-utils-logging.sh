# hack/lib/vendor-bash-utils-logging.sh
#
# shellcheck shell=bash
# shellcheck disable=SC2034

declare -r __lib_vendor_bash_utils_logging_sourced="true"

######################
### Error Messages ###
######################

# declare -r ERROR_FILE_NOT_FOUND="file not found"
#
declare -r ERROR_FILE_NOT_FOUND="failed to find file"

# declare -r ERROR_DIR_NOT_FOUND="directory not found."
#
declare -r ERROR_DIR_NOT_FOUND="directory not found."

# declare -r ERROR_FILE_SOURCE_FAILED="failed to source file"
#
declare -r ERROR_FILE_SOURCE_FAILED="failed to source file."

# declare -r ERROR_ARG_REQUIRED="argument must be provided."
#
declare -r ERROR_ARG_REQUIRED="argument must be provided."

# declare -r ERROR_STRING_EMPTY="string is empty."
#
declare -r ERROR_STRING_EMPTY="string is empty."

# declare -r ERROR_STDIN_NULL="stdin cannot be null."
#
declare -r ERROR_STDIN_NULL="stdin cannot be null."

if ! declare -F REQUIRES_CMDS > /dev/null; then
    declare -r __bash_utils_util_base_lib="hack/vendor/bash-utils/util/base.sh"
    [ -f "$__bash_utils_util_base_lib" ] || "$(echo "$ERROR_FILE_NOT_FOUND: $__bash_utils_util_base_lib"; exit 1)"
    # shellcheck source=../vendor/bash-utils/util/base.sh
    . "$__bash_utils_util_base_lib"
fi

if ! declare -F config_load_all > /dev/null; then
    declare -r __bash_utils_util_config="hack/vendor/bash-utils/util/config.sh"
    [ -f "$__bash_utils_util_config" ] || "$(echo "$ERROR_FILE_NOT_FOUND: $__bash_utils_util_config"; exit 1)"
    # shellcheck source=../vendor/bash-utils/util/config.sh
    . "$__bash_utils_util_config"
fi

if ! declare -F log > /dev/null; then
    declare -r __bash_utils_util_logging_lib="hack/vendor/bash-utils/util/logging.sh"
    [ -f "$__bash_utils_util_logging_lib" ] || "$(echo "$ERROR_FILE_NOT_FOUND: $__bash_utils_util_logging_lib"; exit 1)"
    # shellcheck source=../vendor/bash-utils/util/logging.sh
    . "$__bash_utils_util_logging_lib"
fi

config_load_all BASE_CONFIG_DEFAULTS BASE_CLI_ARGS
