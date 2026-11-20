#!/usr/bin/env bats
#
# Tests for hack/bin/generate-serve-certs.sh.
#
# podman is mocked with bats-mock; openssl is real, so the key and certificate the script hands
# to `podman secret create` are real PEM data. bats-mock only matches as many arguments as a plan
# line has patterns, and runs the plan line's command with all of them in "$@". The
# `secret create` plans use that to record their arguments and stdin under ${TEST_DIR}, since the
# number of --label options varies (podman::secret_create_replace_from_stdin also labels the
# secret with the repo's remote URL when it has one).

load "${PWD}/test/test_helper"

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# podman_secret_create_plan(name)
#
# Prints a bats-mock plan line for one `podman secret create --replace ...` call that records
# its arguments to ${TEST_DIR}/<name>.args and its stdin to ${TEST_DIR}/<name>.pem.
#
# Globals:
#   TEST_DIR   Read; set by common_setup.
# Arguments:
#   $1   The file name to record under ${TEST_DIR}, e.g. key or cert.
# Outputs:
#   The plan line on stdout.
podman_secret_create_plan() {
  local -r name="$1"
  printf '%s' "secret create --replace : printf '%s\n' \"\$@\" > '${TEST_DIR}/${name}.args'; cat > '${TEST_DIR}/${name}.pem'"
}

@test "fails when the environment operand is missing" {
  run hack/bin/generate-serve-certs.sh
  assert_failure
  # shellcheck disable=SC2016  # "$1" is literal text in the message
  assert_output --partial '$1 operand is required'
}

@test "warns and replaces nothing when the ssl-key secret already exists" {
  stub podman "secret exists ssl-key-prod : exit 0"

  run hack/bin/generate-serve-certs.sh prod
  assert_success
  assert_output --partial "podman secret ssl-key-prod already exists. Refusing to replace ssl-key-prod. Delete ssl-key-prod to recreate."

  # Fails if the script went on to call podman again, e.g. to create a secret.
  unstub podman
}

@test "warns and replaces nothing when the ssl-cert secret already exists" {
  stub podman \
    "secret exists ssl-key-prod : exit 1" \
    "secret exists ssl-cert-prod : exit 0"

  run hack/bin/generate-serve-certs.sh prod
  assert_success
  assert_output --partial "podman secret ssl-cert-prod already exists. Refusing to replace ssl-cert-prod. Delete ssl-cert-prod to recreate."

  unstub podman
}

@test "generates a private key and self-signed certificate when neither secret exists" {
  stub podman \
    "secret exists ssl-key-prod : exit 1" \
    "secret exists ssl-cert-prod : exit 1" \
    "$(podman_secret_create_plan key)" \
    "secret inspect --showsecret -f * ssl-key-prod : cat '${TEST_DIR}/key.pem'" \
    "$(podman_secret_create_plan cert)"

  # The options `make generate-serve-certs-prod` passes. None of the Makefile targets pass -n.
  run hack/bin/generate-serve-certs.sh prod \
    -d 365 \
    -a "DNS:r10.expresso.lan" \
    -a "DNS:*.r10.expresso.lan" \
    -a "IP:10.50.0.202"
  assert_success
  assert_output --partial "Self signed certificate saved in podman secret: ssl-cert-prod"

  # The key, stored as ssl-key-prod.
  assert_file_contains "${TEST_DIR}/key.pem" "BEGIN EC PRIVATE KEY"
  assert_file_contains "${TEST_DIR}/key.args" "^ssl-key-prod$"
  assert_file_contains "${TEST_DIR}/key.args" "^--label=ssl=key$"
  assert_file_contains "${TEST_DIR}/key.args" "^--label=environment=prod$"
  assert_file_contains "${TEST_DIR}/key.args" "^--label=type=ssl$"

  # The certificate, signed with that key and stored as ssl-cert-prod.
  assert_file_contains "${TEST_DIR}/cert.pem" "BEGIN CERTIFICATE"
  assert_file_contains "${TEST_DIR}/cert.args" "^ssl-cert-prod$"
  assert_file_contains "${TEST_DIR}/cert.args" "^--label=ssl=cert$"
  assert_file_contains "${TEST_DIR}/cert.args" "^--label=environment=prod$"

  # Exactly the -a values: without -n, no empty "DNS:" name is added.
  run openssl x509 -in "${TEST_DIR}/cert.pem" -noout -ext subjectAltName
  assert_success
  assert_output --partial "DNS:r10.expresso.lan, DNS:*.r10.expresso.lan, IP Address:10.50.0.202"

  unstub podman
}

@test "fails when the private key can't be stored" {
  stub podman \
    "secret exists ssl-key-prod : exit 1" \
    "secret exists ssl-cert-prod : exit 1" \
    "secret create --replace : cat > /dev/null; exit 1"

  run hack/bin/generate-serve-certs.sh prod
  assert_failure
  assert_output --partial "failed to generate and save podman secret: ssl-key-prod"

  # Fails if the script went on to generate the certificate.
  unstub podman
}

@test "fails when the certificate can't be generated" {
  # The stored key reads back as nothing, so openssl::self_signed_cert_gen has no key to sign
  # with and the certificate is never stored.
  stub podman \
    "secret exists ssl-key-prod : exit 1" \
    "secret exists ssl-cert-prod : exit 1" \
    "secret create --replace : cat > /dev/null" \
    "secret inspect --showsecret -f * ssl-key-prod : exit 1"

  run hack/bin/generate-serve-certs.sh prod
  assert_failure
  assert_output --partial "failed to generate self signed certificate and/or failed to create podman secret: ssl-cert-prod"

  unstub podman
}
