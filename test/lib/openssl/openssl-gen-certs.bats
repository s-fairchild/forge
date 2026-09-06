#!/usr/bin/env bats
#
# Tests for hack/lib/openssl/openssl-gen-certs.sh.
#
# See test/test_helper.bash's "IMPORTANT" comment: each @test sources the file under test as
# its own first line, never in setup().
#
# No mocking: openssl is real, deterministic, offline local computation -- tests run it for
# real and decode its output with `openssl x509`/`openssl ec` rather than string-matching PEM.

load "${PWD}/test/test_helper"

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "openssl_gen_private_key produces a valid EC private key" {
  source hack/lib/openssl/openssl-gen-certs.sh
  run openssl_gen_private_key
  assert_success
  assert_output --partial "BEGIN EC PARAMETERS"

  echo "${output}" > "${TEST_DIR}/key.pem"
  run openssl ec -in "${TEST_DIR}/key.pem" -noout -text
  assert_success
  assert_output --partial "prime256v1"
}

@test "usage_openssl_gen_self_signed_certificate prints usage to stderr" {
  source hack/lib/openssl/openssl-gen-certs.sh
  run usage_openssl_gen_self_signed_certificate
  assert_success
  assert_output --partial "Usage: openssl_gen_self_signed_certificate"
}

@test "openssl_gen_self_signed_certificate fails via fatal on empty stdin" {
  run bash -c "source hack/lib/openssl/openssl-gen-certs.sh; openssl_gen_self_signed_certificate < /dev/null"
  assert_failure
}

@test "openssl_gen_self_signed_certificate -h prints usage (reads stdin first, so needs non-empty input)" {
  # openssl_gen_self_signed_certificate reads all of stdin into a local *before* parsing options
  # (and fatally aborts on empty stdin, see the test above) -- so even the -h path needs some
  # non-empty stdin to reach getopts at all. This is pre-existing behavior, not fixed here.
  source hack/lib/openssl/openssl-gen-certs.sh
  run bash -c 'echo dummy | { source hack/lib/openssl/openssl-gen-certs.sh; openssl_gen_self_signed_certificate -h; }'
  assert_success
  assert_output --partial "Usage: openssl_gen_self_signed_certificate"
}

@test "openssl_gen_self_signed_certificate rejects a missing option-argument" {
  run bash -c 'echo dummy | { source hack/lib/openssl/openssl-gen-certs.sh; openssl_gen_self_signed_certificate -d; }'
  assert_failure
  assert_output --partial "required"
}

@test "openssl_gen_self_signed_certificate rejects an unknown option" {
  run bash -c 'echo dummy | { source hack/lib/openssl/openssl-gen-certs.sh; openssl_gen_self_signed_certificate -z; }'
  assert_failure
  assert_output --partial "is unknown"
}

@test "openssl_gen_self_signed_certificate signs a real EC key with the default subject/SANs/expiry" {
  source hack/lib/openssl/openssl-gen-certs.sh
  local key
  key="$(openssl_gen_private_key)"

  run bash -c "echo '${key}' | { source hack/lib/openssl/openssl-gen-certs.sh; openssl_gen_self_signed_certificate; }"
  assert_success
  assert_output --partial "BEGIN CERTIFICATE"

  echo "${output}" > "${TEST_DIR}/cert.pem"
  run openssl x509 -in "${TEST_DIR}/cert.pem" -noout -subject
  assert_success
  assert_output --partial "CN=ignition.local"

  run openssl x509 -in "${TEST_DIR}/cert.pem" -noout -ext subjectAltName
  assert_success
  assert_output --partial "DNS:ignition.local"
  assert_output --partial "DNS:*.ignition.local"
  assert_output --partial "IP Address:127.0.0.1"
}

@test "openssl_gen_self_signed_certificate honors -d/-s/-a overrides" {
  source hack/lib/openssl/openssl-gen-certs.sh
  local key
  key="$(openssl_gen_private_key)"

  run bash -c "echo '${key}' | { source hack/lib/openssl/openssl-gen-certs.sh; openssl_gen_self_signed_certificate -d 30 -s '/CN=custom.local' -a 'DNS:extra.local'; }"
  assert_success

  echo "${output}" > "${TEST_DIR}/cert.pem"
  run openssl x509 -in "${TEST_DIR}/cert.pem" -noout -subject
  assert_success
  assert_output --partial "CN=custom.local"

  run openssl x509 -in "${TEST_DIR}/cert.pem" -noout -ext subjectAltName
  assert_success
  assert_output --partial "DNS:extra.local"
  # -a appends to (doesn't replace) the default SAN list.
  assert_output --partial "DNS:ignition.local"

  run openssl x509 -in "${TEST_DIR}/cert.pem" -noout -enddate
  assert_success
  # -d 30 vs. the default 1825: just confirm the expiry year moved to something well short of
  # the ~5-year default, without pinning an exact date (openssl's "now" and this assertion's
  # "now" could tick over a day boundary between the two calls).
  assert_output --partial "$(date -u -d '+30 days' +%Y)"
}

@test "the double-inclusion guard variable is set after sourcing" {
  source hack/lib/openssl/openssl-gen-certs.sh
  [[ "${__hack_lib_openssl_gen_certs_sourced}" == true ]]
}
