#!/usr/bin/env bats
#
# Tests for hack/bin/k3s-tokens-generate.sh.
#
# Every podman call here (the nested `podman_container` invocation used for the two token
# secrets, plus the volume-export + secret-create pair used for the two filedriver secrets) is
# stubbed via stub_repeated rather than plain stub -- associative array key iteration order
# (podman_filedriver_files) isn't guaranteed, and `< <(process substitution)` runs concurrently
# with its consumer, both of which break bats-mock's normal call-index-based matching (see the
# identical concurrency note in test/bin/kubevirt-vm-up.bats).

load "${PWD}/test/test_helper"

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "-h prints usage and exits 0" {
  run hack/bin/k3s-tokens-generate.sh -h
  assert_success
  assert_output --partial "Usage: k3s-tokens-generate.sh"
}

@test "fails when -p is missing" {
  run hack/bin/k3s-tokens-generate.sh
  assert_failure
  assert_output --partial "-p"
}

@test "rejects an unknown option" {
  run hack/bin/k3s-tokens-generate.sh -z
  assert_failure
  assert_output --partial "is unknown"
}

@test "rejects a missing option-argument" {
  run hack/bin/k3s-tokens-generate.sh -p
  assert_failure
  assert_output --partial "required"
}

@test "generates both k3s tokens and both filedriver secrets on success" {
  # Fully wildcarded: podman_container's exact nested-podman argv (options, image, "podman
  # secret create ...") is already covered by test/lib/podman/podman-container.bats, and
  # podman_volume_export_untar_stdout's by test/lib/podman/podman-volume.bats. This test's job
  # is just proving the entrypoint orchestrates all 4 secret-creation calls successfully.
  stub_repeated podman "* : cat > /dev/null; echo ok"

  run hack/bin/k3s-tokens-generate.sh -p test
  assert_success
  assert_output --partial "Starting podman secret creation"

  unstub podman
}

@test "fails via fatal when creating a token secret fails" {
  stub_repeated podman "* : exit 1"

  run hack/bin/k3s-tokens-generate.sh -p test
  assert_failure

  unstub podman
}

@test "-l appends a --label to the podman secret create options" {
  stub_repeated podman "run * --label=env=test * : cat > /dev/null; echo ok" "* : cat > /dev/null; echo ok"

  run hack/bin/k3s-tokens-generate.sh -p test -l env=test
  assert_success
  assert_output --partial "--label=env=test"

  unstub podman
}
