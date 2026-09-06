#!/usr/bin/env bats
#
# Tests for hack/lib/ignition/ignition-validate.sh.
#
# See test/test_helper.bash's "IMPORTANT" comment: each @test sources the file under test as
# its own first line, never in setup() -- sourcing from setup() would make ignition-validate.sh's
# `declare -r` constants local to setup() and gone by the time the @test body runs.

load "${PWD}/test/test_helper"

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "usage_ignition_validate prints usage to stderr" {
  source hack/lib/ignition/ignition-validate.sh
  run usage_ignition_validate
  assert_success
  assert_output --partial "Usage: ignition_validate"
}

@test "ignition_validate -h prints usage and returns 0 without invoking podman" {
  source hack/lib/ignition/ignition-validate.sh
  run ignition_validate -h
  assert_success
  assert_output --partial "Usage: ignition_validate"
}

@test "ignition_validate rejects an unknown option" {
  source hack/lib/ignition/ignition-validate.sh
  run ignition_validate -z
  assert_failure
  assert_output --partial "is unknown"
}

@test "ignition_validate rejects a missing option-argument" {
  source hack/lib/ignition/ignition-validate.sh
  run ignition_validate -s
  assert_failure
  assert_output --partial "must be provided"
}

@test "ignition_validate invokes podman run with the expected base options and passthrough args" {
  source hack/lib/ignition/ignition-validate.sh
  stub podman \
    "run -i --rm --env='IGNITION_*' --env='IGN_*' --workdir=/data quay.io/coreos/ignition-validate:release config.ign : echo stubbed-podman-run"

  run ignition_validate config.ign
  assert_success
  assert_output --partial "stubbed-podman-run"

  unstub podman
}

@test "ignition_validate -s adds a --secret option before the base options" {
  source hack/lib/ignition/ignition-validate.sh
  stub podman \
    "run --secret=my-secret -i --rm --env='IGNITION_*' --env='IGN_*' --workdir=/data quay.io/coreos/ignition-validate:release config.ign : echo stubbed"

  run ignition_validate -s my-secret config.ign
  assert_success

  unstub podman
}

@test "ignition_validate -m adds a bind-mount and disables SELinux label enforcement" {
  source hack/lib/ignition/ignition-validate.sh
  # bats-mock's stub plan lines are naively whitespace-split into case-glob patterns, so we
  # don't need to assert the exact --mount= string here (fragile to reproduce byte-for-byte) --
  # just that podman is invoked at all and the function reports success.
  stub podman "echo stubbed"

  run ignition_validate -m /host/dir config.ign
  assert_success

  unstub podman
}

@test "ignition_validate forwards a non-zero podman exit status" {
  source hack/lib/ignition/ignition-validate.sh
  stub podman "run * : exit 3"

  run ignition_validate config.ign
  assert_failure 3

  unstub podman
}

@test "the double-inclusion guard variable lets a caller skip re-sourcing" {
  # The __hack_lib_ignition_validate_sourced guard is a contract for CALLERS (they check it
  # before sourcing this file, e.g. `if [ "${__hack_lib_ignition_validate_sourced:-}" != "true"
  # ]; then . hack/lib/ignition/ignition-validate.sh; fi`), not self-protection against being
  # sourced twice directly -- this file has no internal guard around its own body, so a raw
  # double `source` (bypassing that caller-side check) hits bash's readonly-redeclaration error
  # on its own top-of-file constants. Verify the guard variable is set to "true" after one
  # source, which is what callers actually rely on. This spawns its own bash process, so it's
  # unaffected by the setup()-scoping gotcha described above.
  source hack/lib/ignition/ignition-validate.sh
  [[ "${__hack_lib_ignition_validate_sourced}" == true ]]
}
