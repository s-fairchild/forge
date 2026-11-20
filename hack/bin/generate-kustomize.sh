#!/bin/bash
#
# Build every enabled app's kustomize overlay into a directory of manifests.

[[ "${XTRACE:-0}" -eq 1 ]] && set -x

# main(base_dir manifests overlay)
#
# Entry point. Creates <base_dir> and <manifests> if needed, then delegates to
# generate_kube_manifests.
#
# Globals:
#   SCRIPT_NAME   Read to scope the logger's script name.
# Arguments:
#   $1   Root path to search for overlay directories (e.g. pkg).
#   $2   Destination directory for the generated YAML files.
#   $3   Overlay name to match (e.g. "prod", "staging").
# Outputs:
#   Writes generated manifests under <manifests>; log lines.
# Returns:
#   0 on success. Calls fatal or log_fatal (non-zero exit) if an operand is
#   missing, a directory can't be created, or generate_kube_manifests fails.
main() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  set_script_name "${SCRIPT_NAME:-}:${FUNCNAME[0]}"

  core::require_operands 3 "$@" || return
  local -r base="${1}"
  local -r out="${2}"
  local -r overlay="${3}"
  log_debug "$(declare -p base out overlay)"

  mkdir -p "${base}" || {
    core::fail "failed to create directory: ${base}" || return
  }
  mkdir -p "${out}" || {
     core::fail "failed to create directory: ${out}" || return
  }

  if ! generate_kube_manifests "${base}" "${out}" "${overlay}"; then
    core::fail "failed to generate kube manifests." || return
  fi
}

# is_enabled(app enabled)
#
# Tests whether <app> matches the array named by <enabled>, joined into an ERE
# alternation (app1|app2|...). The match is unanchored, so <app> also matches
# when an entry matches only part of its name.
#
# Globals:
#   None.
# Arguments:
#   $1   The application name to test.
#   $2   Nameref: the name of an array of enabled app names (e.g. apps_enabled).
# Outputs:
#   None.
# Returns:
#   0 if <app> matches; 1 otherwise.
is_enabled() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 2 "$@" || return
  local -r app="${1}"
  local -n enabled="${2}"

  local enabled_regex
  enabled_regex="$(IFS='|'; printf '%s' "${enabled[*]}")"
  log_debug "$(declare -p app enabled enabled_regex)"

  [[ "${app}" =~ ${enabled_regex} ]]
}

# get_app_name(path)
#
# Prints the application name for an overlay directory path by walking two
# dirname levels up and taking the basename.
# Example: pkg/workloads/jellyfin/overlays/prod → jellyfin
#
# Globals:
#   None.
# Arguments:
#   $1   Overlay directory path, as found by find.
# Outputs:
#   The application name on stdout.
# Returns:
#   basename's exit status.
get_app_name() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  core::require_operands 1 "$@" || return
  local -r path="${1}"

  basename "$(dirname "$(dirname "${path}")")"
}

# generate_kube_manifests(base dest overlay)
#
# Finds every directory named <overlay> under <base> and, for each one whose app
# is enabled (is_enabled against apps_enabled), runs `kustomize build` on it and
# writes the output to <dest>/<app-name><__manifest_file_extension>. Stops at the
# first build that fails. Apps not listed in apps_enabled are skipped.
#
# Globals:
#   apps_enabled                Read: allow-list of app names, from
#                               hack/etc/kube-manifests-gen.env.
#   __manifest_file_extension   Read: extension of the generated files, from
#                               hack/etc/kube-manifests-gen.env.
# Arguments:
#   $1   Root path to search.
#   $2   Destination directory for the generated YAML files.
#   $3   Directory name to match (e.g. "prod").
# Outputs:
#   Writes one file per enabled app to <dest>; log lines, and an error if no
#   overlay directories are found or a build fails.
# Returns:
#   1 if an operand is missing or no overlay directories are found; 0 otherwise.
generate_kube_manifests() {
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"
  set_script_name "${SCRIPT_NAME:-}:${FUNCNAME[0]}"

  core::require_operands 3 "$@" || return
  local -r pkgs="${1}"
  local -r dest="${2}"
  local -r overlay="${3}"
  log_debug "$(declare -p base dest overlay)"

  local -a pkg_overlays=()
  mapfile -t \
    < <(find "${pkgs}" -type d -name "${overlay}") \
    pkg_overlays

  if [[ ! -v pkg_overlays ]]; then
    core::fail "No overlays were found in ${pkgs}." || return
  fi
  readonly pkg_overlays
  log_debug "$(declare -p pkg_overlays)"

  local manifest_out app_kustomize_base
  for k in "${pkg_overlays[@]}"; do
    app_kustomize_base="$(get_app_name "${k}")"
    log_debug "$(declare -p app_kustomize_base)"

    if is_enabled "${app_kustomize_base}" apps_enabled; then
      manifest_out="${dest}/${app_kustomize_base}${__manifest_out_extension}"
      log_debug "$(declare -p manifest_out)"

      if ! kube::kustomize_build "${k}" > "${manifest_out}"; then
        core::fail "kustomize build failed: ${k}" || return
      fi
      log_info "manifest_out: ${manifest_out}"
    fi
  done
}

# shellcheck source=../vendor/bashkit/local/lib/bashkit/os/bk-bootstrap.sh
. "${BASH_SOURCE[0]%/*}/../vendor/bashkit/local/lib/bashkit/os/bk-bootstrap.sh"
# shellcheck source=../vendor/bash-logger/logging.sh
. /dev/null
# shellcheck source=../vendor/bashkit/local/lib/bashkit/core/logger-utils.sh
. /dev/null
import core/logger-utils.sh
# shellcheck source=../etc/kube-manifests-gen.env
. /dev/null
import "${BASH_SOURCE[0]%/*}/../etc/kube-manifests-gen.env"
# shellcheck source=../vendor/bashkit/local/lib/bashkit/kube/kube.sh
. /dev/null
import kube/kube.sh

core::logger_init --name "$(basename "$0")"

main "$@"
