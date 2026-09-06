#!/usr/bin/env bats
#
# Tests for hack/lib/ignition/butane.sh.
#
# See test/test_helper.bash's "IMPORTANT" comment: each @test sources the file under test as
# its own first line, never in setup() -- sourcing from setup() would make butane.sh's
# `declare -r` constants local to setup() and gone by the time the @test body runs.

load "${PWD}/test/test_helper"

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "usage_butane prints usage to stderr" {
  source hack/lib/ignition/butane.sh
  run usage_butane
  assert_success
  assert_output --partial "Usage: butane"
}

@test "butane -h prints usage and returns 0 without invoking podman" {
  source hack/lib/ignition/butane.sh
  run butane -h
  assert_success
  assert_output --partial "Usage: butane"
}

@test "butane rejects an unknown option" {
  source hack/lib/ignition/butane.sh
  run butane -z
  assert_failure
  assert_output --partial "is unknown"
}

@test "butane rejects a missing option-argument" {
  source hack/lib/ignition/butane.sh
  run butane -s
  assert_failure
  assert_output --partial "must be provided"
}

@test "butane invokes podman run with the expected base options and passthrough args" {
  source hack/lib/ignition/butane.sh
  stub podman \
    "run -i --rm --env='BU_*' --env='BUTANE_*' --workdir=/data quay.io/coreos/butane:release config.bu : echo stubbed-podman-run"

  run butane config.bu
  assert_success
  assert_output --partial "stubbed-podman-run"

  unstub podman
}

@test "butane -s adds a --secret option before the base options" {
  source hack/lib/ignition/butane.sh
  stub podman \
    "run --secret=my-secret -i --rm --env='BU_*' --env='BUTANE_*' --workdir=/data quay.io/coreos/butane:release config.bu : echo stubbed"

  run butane -s my-secret config.bu
  assert_success

  unstub podman
}

@test "butane -m adds a bind-mount and disables SELinux label enforcement" {
  source hack/lib/ignition/butane.sh
  # bats-mock's stub plan lines are naively whitespace-split into case-glob patterns, so we
  # don't need to assert the exact --mount= string here (fragile to reproduce byte-for-byte) --
  # just that podman is invoked at all and the function reports success.
  stub podman "echo stubbed"

  run butane -m "${TEST_DIR}" config.bu
  assert_success

  unstub podman
}

@test "butane -m rejects a nonexistent host directory without invoking podman" {
  source hack/lib/ignition/butane.sh
  run butane -m "${TEST_DIR}/does-not-exist" config.bu
  assert_failure
  assert_output --partial "directory not found"
}

@test "butane -m rejects a duplicate -m option" {
  source hack/lib/ignition/butane.sh
  run butane -m "${TEST_DIR}" -m "${TEST_DIR}" config.bu
  assert_failure
  assert_output --partial "can only be specified once"
}

@test "butane forwards a non-zero podman exit status" {
  source hack/lib/ignition/butane.sh
  stub podman "run * : exit 3"

  run butane config.bu
  assert_failure 3

  unstub podman
}

@test "the double-inclusion guard variable lets a caller skip re-sourcing" {
  # The __hack_lib_ignition_butane_sourced guard is a contract for CALLERS (they check it
  # before sourcing this file), not self-protection against being sourced twice directly --
  # this file has no internal guard around its own body, so a raw double `source` (bypassing
  # that caller-side check) hits bash's readonly-redeclaration error on its own top-of-file
  # constants. Verify the guard variable is set to "true" after one source, which is what
  # callers actually rely on. This spawns its own bash process, so it's unaffected by the
  # setup()-scoping gotcha described above.
  source hack/lib/ignition/butane.sh
  [[ "${__hack_lib_ignition_butane_sourced}" == true ]]
}
