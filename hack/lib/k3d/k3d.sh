# shellcheck shell=bash
#
# k3d cluster helpers: create, delete, and test for a cluster, read its name from a
# k3d config, and merge its kubeconfig into the user's. k3d runs through sudo
# (k3d::sudo_k3d), since the clusters are rootful.

# k3d::sudo_k3d(args...)
#
# Runs `sudo k3d <args>`.
#
# Globals:
#   None.
# Arguments:
#   $@   Passed to k3d. At least two are required (e.g. `cluster list`).
# Outputs:
#   Whatever k3d writes; an error and stack trace if fewer than two arguments are
#   given.
# Returns:
#   1 if fewer than two arguments are given; k3d's exit status otherwise.
k3d::sudo_k3d() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  core::require_operands 2 "$@" || return
  sudo k3d "$@"
}

# k3d::cluster_exists(cluster)
#
# Tests whether a k3d cluster named <cluster> exists, with `k3d cluster list
# <cluster>`.
#
# Globals:
#   None.
# Arguments:
#   $1   The cluster name.
# Outputs:
#   None; k3d's output is discarded. An error and stack trace if <cluster> is
#   missing.
# Returns:
#   0 if the cluster exists; non-zero otherwise.
k3d::cluster_exists() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  core::require_operands 1 "$@" || return
  local -r cluster="${1}"

  k3d::sudo_k3d cluster list "${cluster}" >/dev/null 2>&1
}

# k3d::cluster_delete(cluster)
#
# Deletes the k3d cluster <cluster>. Unlike k3d::cluster_create, this is not
# idempotent: a missing cluster is an error.
#
# Globals:
#   None.
# Arguments:
#   $1   The cluster name.
# Outputs:
#   An info line before deleting; an error if the cluster doesn't exist or the
#   delete fails.
# Returns:
#   1 if <cluster> is missing, the cluster doesn't exist, or `k3d cluster delete`
#   fails; 0 otherwise.
k3d::cluster_delete() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  core::require_operands 1 "$@" || return
  local -r cluster="${1}"

  if ! k3d::cluster_exists "${cluster}"; then
    log_error "k3d cluster '${cluster}' does not exist; nothing to delete"
    return 1
  fi

  log_info "Deleting k3d cluster '${cluster}'"
  if ! k3d::sudo_k3d cluster delete "${cluster}"; then
    log_error "k3d cluster delete ${cluster} failed"
    return 1
  fi
}

# k3d::cluster_create(cluster config)
#
# Creates a k3d cluster with `k3d cluster create --config`, unless a cluster named
# <cluster> already exists. <config> is passed as ${PWD}/<config>, so it must be
# relative to the current directory.
#
# Globals:
#   PWD   Read to make <config> absolute for sudo.
# Arguments:
#   $1   The cluster name, as given in <config>'s .metadata.name.
#   $2   Path to the k3d.io/v1alpha5 Simple cluster config, relative to the
#        current directory.
# Outputs:
#   A notice if the cluster already exists, otherwise an info line and k3d's
#   output; an error if the create fails.
# Returns:
#   1 if an operand is missing or `k3d cluster create` fails; 0 otherwise,
#   including when the cluster already exists.
k3d::cluster_create() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  core::require_operands 2 "$@" || return
  local -r cluster="${1}"
  local -r config="${2}"

  if k3d::cluster_exists "${cluster}"; then
    log_notice "k3d cluster ${cluster} already exists."
    return 0
  fi

  log_info "Creating k3d cluster '${cluster}' from ${config}"
  k3d::sudo_k3d cluster create --config "${PWD}/${config}" || {
    log_error "k3d cluster create ${cluster} failed"
    return 1
  }
}

# k3d::get_cluster_name_from_config(config)
#
# Prints the cluster name from a k3d config's .metadata.name, read with core::yq
# and checked with core::yq_validate_output.
#
# Globals:
#   None.
# Arguments:
#   $1   Path to the k3d.io/v1alpha5 Simple cluster config.
# Outputs:
#   The cluster name on stdout, with no trailing newline. An error and stack trace
#   if <config> is missing, empty, or not a file, or if .metadata.name can't be
#   read or is empty.
# Returns:
#   1 on any of the failures above; 0 otherwise.
k3d::get_cluster_name_from_config() {
  core::require_operands 1 "$@" || return
  local -r config="${1}"

  [[ -n "${config}" ]] || { core::fail "config=\$1 cannot be empty string." || return; }
  [[ -f "${config}" ]] || { core::fail "file not found: ${config}" || return; }

  local -r metadata_name_key='.metadata.name'
  local cluster
  cluster="$(
    core::yq eval \
      "${metadata_name_key}" \
      "${config}" \
      || { core::fail "failed to read .metadata.name from ${config}" || return; }
  )"
  readonly cluster
  log_debug "$(declare -p cluster)"

  core::yq_validate_output "${cluster}" \
    "${metadata_name_key}" \
    "${config}" \
    || return

  printf "%s" "${cluster}"
}

# k3d::merge_kubeconfig_with_user(config kubeconfig)
#
# Merges the kubeconfig of the cluster named in <config> into <kubeconfig> with
# `k3d kubeconfig merge`, gives the file back to $USER (k3d runs as root), and
# rewrites the server address from <config>'s .kubeAPI.host to .kubeAPI.hostIP,
# keeping .kubeAPI.hostPort. sed leaves a backup at <kubeconfig>~.
#
# Globals:
#   USER   Read as the kubeconfig's new owner.
# Arguments:
#   $1   Path to the k3d.io/v1alpha5 Simple cluster config.
#   $2   Path to the kubeconfig to merge into, e.g. ~/.kube/config.
# Outputs:
#   Info lines for each step; an error and stack trace if .kubeAPI.host, .hostIP
#   or .hostPort is missing from <config>.
# Returns:
#   1 if an operand is missing or a .kubeAPI field is empty; sed's exit status
#   otherwise. The cluster name lookup, k3d, and chown steps aren't checked, so
#   their failures stop the function only under errexit.
k3d::merge_kubeconfig_with_user() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  core::require_operands 2 "$@" || return
  local -r config="${1}"
  local -r kubeconfig="${2}"

  local cluster
  cluster="$(k3d::get_cluster_name_from_config "${config}")"

  log_info "Merging ${cluster} kubeconfig with ${kubeconfig}"
  k3d::sudo_k3d kubeconfig \
    merge \
    "${cluster}" \
    -o "${kubeconfig}"

  log_info "Resetting owner and group permissions of ${kubeconfig}"
  sudo chown "${USER}:" "${kubeconfig}"

  local -r kubeapi_key='.kubeAPI'
  local host hostIP hostPort
  eval "$(
    core::yq eval \
      "${kubeapi_key}" \
      "${config}" \
      -o shell
  )"
  readonly host hostIP hostPort

  local e
  for e in host hostIP hostPort; do
    core::yq_validate_output "${!e}" \
      "${kubeapi_key}.${e}" \
      "${config}" \
      || return
  done

  log_info "Updating server name in ${kubeconfig}"
  sed -i~ \
    "s/${host}:${hostPort}/${hostIP}:${hostPort}/" \
    "${kubeconfig}"
}

# shellcheck source=../git/submodule.sh
. "${BASH_SOURCE[0]%/*}/../git/submodule.sh"
git::submodule_require "${BASH_SOURCE[0]%/*}/../../vendor/bash-logger/logging.sh" \
  || return
git::submodule_require "${BASH_SOURCE[0]%/*}/../../vendor/bashkit/local/lib/bashkit/core/logger-utils.sh" \
  || return

# shellcheck source=../../vendor/bashkit/local/lib/bashkit/core/logger-utils.sh
. "${BASH_SOURCE[0]%/*}/../../vendor/bashkit/local/lib/bashkit/core/logger-utils.sh"

# shellcheck source=../../vendor/bashkit/local/bin/yq
. "${BASH_SOURCE[0]%/*}/../../vendor/bashkit/local/bin/yq"

# shellcheck source=../../vendor/bashkit/local/lib/bashkit/core/yq-utils.sh
. "${BASH_SOURCE[0]%/*}/../../vendor/bashkit/local/lib/bashkit/core/yq-utils.sh"
