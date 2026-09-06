#!/usr/bin/env bats
#
# Tests for hack/lib/checksum/checksum.sh (the format.sh + sha512sum.sh aggregator).

load "${PWD}/test/test_helper"

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "sourcing checksum.sh pulls in both format.sh and sha512sum.sh" {
  run bash -c '
    source hack/lib/checksum/checksum.sh
    declare -F checksum_parse_hash > /dev/null &&
    declare -F checksum_format_verification_hash_sha512 > /dev/null &&
    declare -F sha512sum_gen > /dev/null &&
    declare -F sha512sum_check > /dev/null
  '
  assert_success
}

@test "sourcing checksum.sh twice does not error" {
  run bash -c '
    source hack/lib/checksum/checksum.sh
    source hack/lib/checksum/checksum.sh
  '
  assert_success
}
