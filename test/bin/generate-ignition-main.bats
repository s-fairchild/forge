#!/usr/bin/env bats
#
# Tests for hack/bin/generate-ignition-main.sh.
#
# hack/bin/*.sh entry points call `main "$@"` unconditionally as their last line, so they can't
# be sourced for isolated function testing the way hack/lib/*.sh files can (see
# test/test_helper.bash). Every test here instead executes the script directly (it's a real
# executable with a #!/bin/bash shebang) via `run`, which also keeps $0 correct for its usage
# text -- unlike `source`, which would leave $0 as bats' own argv[0].

load "${PWD}/test/test_helper"

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "-h prints usage and exits 0" {
  run hack/bin/generate-ignition-main.sh -h
  assert_success
  assert_output --partial "Usage: generate-ignition-main.sh"
}

@test "fails when -f is missing" {
  run hack/bin/generate-ignition-main.sh -p prod
  assert_failure
  assert_output --partial "-f"
}

@test "fails when -p is missing" {
  local -r butane_file="${TEST_DIR}/main.bu"
  : > "${butane_file}"
  run hack/bin/generate-ignition-main.sh -f "${butane_file}"
  assert_failure
  assert_output --partial "-p"
}

@test "fails when the butane file does not exist" {
  run hack/bin/generate-ignition-main.sh -f "${TEST_DIR}/missing.bu" -p prod
  assert_failure
  assert_output --partial "file not found"
}

@test "fails on an unknown option" {
  run hack/bin/generate-ignition-main.sh -z
  assert_failure
  assert_output --partial "is unknown"
}
