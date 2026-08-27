#!/bin/bash
# Idempotently define a libvirt network/pool/volume from a domain-specific set of
# <libvirt_dir>/*.xml templates and launch the domain as a transient VM, with the
# ignition secret merged into its qemu:commandline fw_cfg arg at launch time so it
# never touches a git-tracked or persisted-to-disk domain XML.
#
# Every libvirt object name and the XML template directory are supplied by the
# caller (see usage()) rather than hardcoded, so this one script can be reused
# across multiple make targets for different VM domains -- see
# deploy/installer/etc/libvirt/*.env for the per-domain values and
# deploy/installer/Makefile's install-staging-vm target for how they're sourced
# and passed through.

[ "${XTRACE:-0}" -eq 1 ] && set -x

set -o nounset \
    -o errexit \
    -o pipefail \
    -o noclobber \
    -o hashall

usage() {
    cat <<USAGE >&2
Usage: ${0##*/} -l libvirt_dir -n network_name -p pool_name -d volume_name -m domain_name [-s ignition_secret] [-v] [-q] [-h]

Idempotently defines a libvirt network, storage pool, and overlay disk volume from
<libvirt_dir>/*.xml, then launches <domain_name> as a transient domain (virsh create)
with the given podman secret's contents merged into a qemu:commandline -fw_cfg
opt/com.coreos/config arg at launch time.

Options:
    -l libvirt_dir       Directory containing network.xml, pool.xml, volume.xml, and
                          domain.xml for this VM domain (e.g. deploy/libvirt/staging).
    -n network_name       libvirt network name to define/activate/autostart.
    -p pool_name          libvirt storage pool name to define/build/start/autostart.
    -d volume_name        Overlay disk volume name to create in the pool.
    -m domain_name        libvirt domain (VM) name to launch.
    -s ignition_secret    Podman secret name holding the ignition JSON to boot with.
                           (default: ignition-staging)
    -v                    Enable verbose/DEBUG-level logging for this invocation, overriding VERBOSE/DEBUG.
    -q                    Suppress console logging for this invocation, overriding QUIET.
    -h                    Print this help message and exit.
USAGE
}

ensure_network() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    require_operands 2 "$@" || return 1
    local -r libvirt_dir="$1" network_name="$2"

    if virsh_net_is_defined "$network_name"; then
        info "libvirt network '$network_name' already defined"
    else
        virsh net-define "${libvirt_dir}/network.xml"
    fi
    virsh_net_is_active "$network_name" || virsh_net_activate "$network_name"
    virsh_net_autostart "$network_name"
}

ensure_pool() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    require_operands 2 "$@" || return 1
    local -r libvirt_dir="$1" pool_name="$2"

    if virsh_pool_is_defined "$pool_name"; then
        info "libvirt pool '$pool_name' already defined"
    else
        local pool_xml
        pool_xml="$(<"${libvirt_dir}/pool.xml")"
        pool_xml="${pool_xml//\$HOME/$HOME}"
        printf '%s' "$pool_xml" | virsh_pool_define /dev/stdin
        unset pool_xml
    fi
    # pool-build fails outright against an already-active pool (regardless of pool
    # type), so only build+start together on the first run.
    if virsh_pool_is_active "$pool_name"; then
        info "libvirt pool '$pool_name' already active"
    else
        virsh_pool_build "$pool_name"
        virsh_pool_start "$pool_name"
    fi
    virsh_pool_autostart "$pool_name"
}

ensure_volume() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    require_operands 3 "$@" || return 1
    local -r libvirt_dir="$1" pool_name="$2" volume_name="$3"

    if virsh_vol_is_present "$pool_name" "$volume_name"; then
        info "volume '$volume_name' already present in pool '$pool_name'"
    else
        local volume_xml
        volume_xml="$(<"${libvirt_dir}/volume.xml")"
        volume_xml="${volume_xml//\$HOME/$HOME}"
        printf '%s' "$volume_xml" | virsh_vol_create "$pool_name" /dev/stdin
        unset volume_xml
    fi
}

launch_domain() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
    require_operands 3 "$@" || return 1
    local -r libvirt_dir="$1" domain_name="$2" ignition_secret="$3"

    if virsh_dom_is_active "$domain_name"; then
        info "domain '$domain_name' is already running"
        return 0
    fi

    # xtrace must be off before the secret is read into the shell, not just before
    # it's used -- it's the trace line's expanded arguments that would leak the
    # value, not the command's result.
    # shellcheck disable=SC2034 # populated via nameref inside with_xtrace_suppressed
    local -i ignition_xtrace_was_on=0
    with_xtrace_suppressed save ignition_xtrace_was_on

    local ignition merged_xml
    ignition="$(podman_secret_showsecret "$ignition_secret")"
    # QEMU's -fw_cfg option is itself comma-separated (name=...,string=...); a literal
    # comma anywhere in the ignition JSON must be doubled or QEMU misparses everything
    # after the first one as bogus sub-options.
    ignition="${ignition//,/,,}"
    merged_xml="$(virt-xml --edit \
                            --qemu-commandline="-fw_cfg name=opt/com.coreos/config,string=${ignition}" \
                            --print-xml \
                            < "${libvirt_dir}/domain.xml")"
    unset ignition

    printf '%s' "$merged_xml" | virsh_dom_create /dev/stdin
    unset merged_xml

    with_xtrace_suppressed restore ignition_xtrace_was_on
}

main() {
    debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

    local ignition_secret="" libvirt_dir="" network="" pool="" volume="" domain=""
    local opt
    local -i OPTIND=1 cli_verbose=0 cli_quiet=0
    while getopts ':s:n:p:d:l:m:vqh' opt; do
        case "$opt" in
            s)
                is_option_arg_dup "$opt" "$ignition_secret"
                ignition_secret="$OPTARG"
                ;;
            n)
                is_option_arg_dup "$opt" "$network"
                network="$OPTARG"
                ;;
            p)
                is_option_arg_dup "$opt" "$pool"
                pool="$OPTARG"
                ;;
            d)
                is_option_arg_dup "$opt" "$volume"
                volume="$OPTARG"
                ;;
            l)
                is_option_arg_dup "$opt" "$libvirt_dir"
                libvirt_dir="$OPTARG"
                ;;
            m)
                is_option_arg_dup "$opt" "$domain"
                domain="$OPTARG"
                ;;
            v) cli_verbose=1 ;;
            q) cli_quiet=1 ;;
            h) usage; exit 0 ;;
            :) usage; fatal "-${OPTARG} $ERROR_OPTION_REQUIRED" ;;
            ?) usage; fatal "-${OPTARG} $ERROR_OPTION_UNKNOWN" ;;
        esac
    done
    shift $((OPTIND - 1))

    bash_logger_adapter_apply_overrides "$cli_verbose" \
                                        "$cli_quiet" \
                                        "$__bash_logger_adapter_env_log_level"

    : "${ignition_secret:=ignition-staging}"
    [ -n "$libvirt_dir" ] || { usage; fatal "-l $ERROR_OPTION_REQUIRED"; }
    [ -n "$network" ]     || { usage; fatal "-n $ERROR_OPTION_REQUIRED"; }
    [ -n "$pool" ]        || { usage; fatal "-p $ERROR_OPTION_REQUIRED"; }
    [ -n "$volume" ]      || { usage; fatal "-d $ERROR_OPTION_REQUIRED"; }
    [ -n "$domain" ]      || { usage; fatal "-m $ERROR_OPTION_REQUIRED"; }

    ensure_network "$libvirt_dir" "$network"
    ensure_pool "$libvirt_dir" "$pool"
    ensure_volume "$libvirt_dir" "$pool" "$volume"
    launch_domain "$libvirt_dir" "$domain" "$ignition_secret"
}

if [ "${__bash_logger_adapter_sourced:-}" != "true" ]; then
    declare __bash_logger_adapter_path="hack/vendor/bash-logger-adapter/adapter.sh"
    [ -f "$__bash_logger_adapter_path" ] || { printf '%s\n' "failed to find file: $__bash_logger_adapter_sourced" >&2; exit 1; }
    # shellcheck source=../vendor/bash-logger-adapter/adapter.sh
    . "$__bash_logger_adapter_path"
    unset __bash_logger_adapter_path
fi

if [ "${__vendor_bashkit_local_lib_bashkit_options_operands_utils_sourced:-}" != "true" ]; then
    declare __vendor_bashkit_local_lib_bashkit_options_operands_utils="hack/vendor/bashkit/local/lib/bashkit/options-operands-utils.sh"
    [ -f "$__vendor_bashkit_local_lib_bashkit_options_operands_utils" ] || fatal "${ERROR_FILE_NOT_FOUND}: ${__vendor_bashkit_local_lib_bashkit_options_operands_utils}"
    # shellcheck source=../vendor/bashkit/local/lib/bashkit/options-operands-utils.sh
    . "$__vendor_bashkit_local_lib_bashkit_options_operands_utils"
    unset __vendor_bashkit_local_lib_bashkit_options_operands_utils
fi

if [ "${__lib_podman_secret_sourced:-}" != "true" ]; then
    declare podman_secrets="hack/lib/podman/podman-secret.sh"
    [ -f "$podman_secrets" ] || { printf '%s\n' "failed to find file: $podman_secrets" >&2; exit 1; }
    # shellcheck source=../lib/podman/podman-secret.sh
    . "$podman_secrets"
    unset podman_secrets
fi

if [ "${__vendor_bashkit_lib_virsh_network_sourced:-}" != "true" ]; then
    declare virsh_network="hack/vendor/bashkit/local/lib/bashkit/virsh/virsh-network.sh"
    [ -f "$virsh_network" ] || fatal "$ERROR_FILE_NOT_FOUND: $virsh_network"
    # shellcheck source=../vendor/bashkit/local/lib/bashkit/virsh/virsh-network.sh
    . "$virsh_network"
    unset virsh_network
fi

if [ "${__vendor_bashkit_lib_virsh_pool_sourced:-}" != "true" ]; then
    declare virsh_pool="hack/vendor/bashkit/local/lib/bashkit/virsh/virsh-pool.sh"
    [ -f "$virsh_pool" ] || fatal "$ERROR_FILE_NOT_FOUND: $virsh_pool"
    # shellcheck source=../vendor/bashkit/local/lib/bashkit/virsh/virsh-pool.sh
    . "$virsh_pool"
    unset virsh_pool
fi

if [ "${__vendor_bashkit_lib_virsh_domain_sourced:-}" != "true" ]; then
    declare virsh_domain="hack/vendor/bashkit/local/lib/bashkit/virsh/virsh-domain.sh"
    [ -f "$virsh_domain" ] || fatal "$ERROR_FILE_NOT_FOUND: $virsh_domain"
    # shellcheck source=../vendor/bashkit/local/lib/bashkit/virsh/virsh-domain.sh
    . "$virsh_domain"
    unset virsh_domain
fi

main "$@"
