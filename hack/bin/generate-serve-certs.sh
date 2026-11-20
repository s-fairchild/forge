#!/bin/bash
#
# Generate a self-signed TLS key and certificate for serving ignition, stored as
# podman secrets.

# main(environment [cert_options...])
#
# Generates an nginx TLS private key with openssl::private_key_gen and a
# self-signed certificate with openssl::self_signed_cert_gen, storing them as the
# podman secrets ssl-key-<environment> and ssl-cert-<environment> for use by the
# ignition serving container. Does nothing if either secret already exists.
#
# Globals:
#   SCRIPT_NAME   Read to scope the logger's script name.
# Arguments:
#   $1   Environment name used to derive the ssl-key-<environment> and
#        ssl-cert-<environment> podman secret names.
#   $@   Remaining operands, passed to openssl::self_signed_cert_gen.
# Outputs:
#   Writes progress/warning log lines; the generated key and certificate are
#   stored as podman secrets, not printed.
# Returns:
#   0 on success, including the no-op case where either secret already
#   exists. 1 if the environment operand is missing, or (after a fatal log
#   line) if key/certificate generation or secret storage fails.
main() {
  set_script_name "${SCRIPT_NAME:-}:${FUNCNAME[0]}"
  log_debug "Starting ${FUNCNAME[0]}($(IFS=' '; echo "$*"))"

  core::require_operands 1 "$@" || return
  local -r environment="$1"
  shift

  local -r key_name="ssl-key-${environment}" cert_name="ssl-cert-${environment}"
  log_debug "$(declare -p environment key_name cert_name)"

  if podman::secret_exists "${key_name}"; then
    log_warn "podman secret ${key_name} already exists. Refusing to replace ${key_name}. Delete ${key_name} to recreate."
    return 0
  elif podman::secret_exists "${cert_name}"; then
    log_warn "podman secret ${cert_name} already exists. Refusing to replace ${cert_name}. Delete ${cert_name} to recreate."
    return 0
  fi

  local -a labels_common=(
    "-l"
    "environment=${environment}"
    "-l"
    "type=ssl"
  )

  log_info "Generating ssl private key... saving to podman secret: ${key_name}"
  openssl::private_key_gen \
    | podman::secret_create_replace_from_stdin \
      "${labels_common[@]}" \
      -l "ssl=key" \
      "${key_name}" \
    || {
      core::print_stack_trace
      log_fatal "failed to generate and save podman secret: ${key_name}"
      # log_fatal only logs.
      return 1
    }

  log_info "Generating self signed certificate..."
  if podman::secret_showsecret "${key_name}" \
    | openssl::self_signed_cert_gen "$@" \
    | podman::secret_create_replace_from_stdin \
      "${labels_common[@]}" \
      -l "ssl=cert" \
      "${cert_name}"; then

      log_info "Self signed certificate saved in podman secret: ${cert_name}"
  else
    core::print_stack_trace
    log_fatal "failed to generate self signed certificate and/or failed to create podman secret: ${cert_name}"
    return 1
  fi
}

# shellcheck source=../lib/git/submodule.sh
. "${BASH_SOURCE[0]%/*}/../lib/git/submodule.sh"
git::submodule_require "${BASH_SOURCE[0]%/*}/../vendor/bashkit/local/lib/bashkit/os/bk-bootstrap.sh"

# Sourced, not imported: `import` is defined by the bootstrap itself.
# shellcheck source=../vendor/bashkit/local/lib/bashkit/os/bk-bootstrap.sh
. "${BASH_SOURCE[0]%/*}/../vendor/bashkit/local/lib/bashkit/os/bk-bootstrap.sh"
# shellcheck source=../vendor/bashkit/local/lib/bashkit/openssl/cert-utils.sh
import "${BASH_SOURCE[0]%/*}/../vendor/bashkit/local/lib/bashkit/openssl/cert-utils.sh"
# shellcheck source=../vendor/bashkit/local/lib/bashkit/podman/podman-secret.sh
import "${BASH_SOURCE[0]%/*}/../vendor/bashkit/local/lib/bashkit/podman/podman-secret.sh"

core::logger_init --name "$(basename "$0")"

main "$@"
