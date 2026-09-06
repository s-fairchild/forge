#!/usr/bin/env bats
#
# Tests for hack/bin/generate-serve-certs.sh.

load "${PWD}/test/test_helper"

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "fails when the environment operand is missing" {
  run hack/bin/generate-serve-certs.sh
  assert_failure
  assert_output --partial '$1'
}

@test "warns and no-ops when the ssl-key secret already exists" {
  stub podman "secret exists ssl-key-prod : exit 0"

  run hack/bin/generate-serve-certs.sh prod
  assert_success
  assert_output --partial "ssl-key-prod already exists"

  unstub podman
}

@test "warns and no-ops when the ssl-cert secret already exists" {
  stub podman \
    "secret exists ssl-key-prod : exit 1" \
    "secret exists ssl-cert-prod : exit 0"

  run hack/bin/generate-serve-certs.sh prod
  assert_success
  assert_output --partial "ssl-cert-prod already exists"

  unstub podman
}

@test "generates a private key and self-signed certificate when neither secret exists" {
  # bats-mock matches patterns positionally per-argument (no true multi-arg wildcard), so
  # patterns here only pin the leading verbs -- trailing --label=.../secret-name/- arguments
  # aren't checked. Exact argument construction is covered by test/lib/podman/podman-secret.bats.
  stub podman \
    "secret exists ssl-key-prod : exit 1" \
    "secret exists ssl-cert-prod : exit 1" \
    "secret create --replace : cat > /dev/null" \
    "secret inspect --showsecret : openssl ecparam -name prime256v1 -genkey" \
    "secret create --replace : cat > /dev/null"

  run hack/bin/generate-serve-certs.sh prod -d 30
  assert_success

  unstub podman
}
