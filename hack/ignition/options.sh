#!/bin/bash

# declare -r __options_sourced="true"
declare -r __options_sourced="true"


collect_user_options() {
    local -n opts="$1"
    while getopts ':kb:' opt; do
        case "${opt}" in
            b)
                # shellcheck disable=SC2034
                opts["BUTANE_MAIN"]="${OPTARG}"
                ;;
            k)

                ;;
            ?)
                echo 
                ;;
            *)
                usage
                ;;
        esac
    done
}

usage() {
    echo
}
