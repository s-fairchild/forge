#!/usr/bin/env bats
#
# Tests for hack/lib/checksum/format.sh.
#
# Uses `run --separate-stderr`, which requires bats >= 1.5.0.
bats_require_minimum_version 1.5.0

load "${PWD}/test/test_helper"

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "checksum_parse_hash extracts the first field of a checksum-tool line" {
  source hack/lib/checksum/format.sh
  run checksum_parse_hash "deadbeef  -"
  assert_success
  assert_output "deadbeef"
}

@test "checksum_parse_hash extracts the hash from a plain digest with no filename field" {
  source hack/lib/checksum/format.sh
  run checksum_parse_hash "deadbeef"
  assert_success
  assert_output "deadbeef"
}

@test "checksum_parse_hash fails when the input is empty" {
  source hack/lib/checksum/format.sh
  run checksum_parse_hash ""
  assert_failure
}

@test "checksum_parse_hash fails when called with no operand" {
  source hack/lib/checksum/format.sh
  run checksum_parse_hash
  assert_failure
}

@test "checksum_format_verification_hash_sha512 formats stdin input as sha512-<hex>" {
  source hack/lib/checksum/format.sh
  printf 'deadbeef  -' > "${TEST_DIR}/input"

  run checksum_format_verification_hash_sha512 < "${TEST_DIR}/input"
  assert_success
  assert_output "sha512-deadbeef"
}

@test "checksum_format_verification_hash_sha512 on empty stdin returns a bare 'sha512-' (pre-existing quirk)" {
  source hack/lib/checksum/format.sh
  # [[ ! -t 0 ]] is true for any non-interactive bats invocation, so this function always reads
  # stdin first regardless of whether $1 was also passed -- its $1-only branch is only reachable
  # with a real tty attached to stdin, which bats can't provide.
  #
  # This is NOT the "fails" case it might look like: checksum_parse_hash's failure (logged error,
  # return 1) happens inside a `$(...)` command substitution used as printf's *argument*, so its
  # exit status is discarded -- the enclosing function's own exit status is printf's (always 0).
  # The net effect is a silently-malformed "sha512-" output on empty input, not a propagated
  # failure. This is pre-existing behavior carried over unchanged by the style rewrite (not one
  # of the named, approved bug fixes), so the test documents the actual behavior rather than the
  # behavior the doc comment implies.
  run --separate-stderr checksum_format_verification_hash_sha512 < /dev/null
  assert_success
  assert_output "sha512-"
}
