#!/usr/bin/env bats
#
# Tests for hack/lib/podman/podman-volume.sh.
#
# See test/test_helper.bash's "IMPORTANT" comment: each @test sources the file under test as
# its own first line, never in setup().

load "${PWD}/test/test_helper"

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "podman_volume_exists returns success when the volume exists" {
  source hack/lib/podman/podman-volume.sh
  stub podman "volume exists my-vol : exit 0"

  run podman_volume_exists my-vol
  assert_success

  unstub podman
}

@test "podman_volume_exists returns failure and logs an error when the volume is missing" {
  source hack/lib/podman/podman-volume.sh
  stub podman "volume exists my-vol : exit 1"

  run podman_volume_exists my-vol
  assert_failure
  assert_output --partial "not found"

  unstub podman
}

@test "podman_volume_create skips creation and warns when the volume already exists" {
  source hack/lib/podman/podman-volume.sh
  stub podman "volume exists my-vol : exit 0"

  run podman_volume_create my-vol
  assert_success
  assert_output --partial "already exists"

  unstub podman
}

@test "podman_volume_create creates the volume when it does not exist" {
  source hack/lib/podman/podman-volume.sh
  stub podman \
    "volume exists my-vol : exit 1" \
    "volume create --ignore --label project=* my-vol : echo volume-created"

  run podman_volume_create my-vol
  assert_success
  assert_output --partial "volume-created"

  unstub podman
}

@test "podman_volume_create fails via fatal when podman volume create fails" {
  source hack/lib/podman/podman-volume.sh
  stub podman \
    "volume exists my-vol : exit 1" \
    "volume create --ignore --label project=* my-vol : exit 1"

  run podman_volume_create my-vol
  assert_failure
  assert_output --partial "Failed to create podman volume"

  unstub podman
}

@test "podman_volume_export_untar_stdout extracts the requested member to stdout" {
  source hack/lib/podman/podman-volume.sh
  mkdir -p "${TEST_DIR}/tarsrc"
  printf 'hello-content' > "${TEST_DIR}/tarsrc/myfile.txt"
  tar -cf "${TEST_DIR}/vol.tar" -C "${TEST_DIR}/tarsrc" myfile.txt

  stub podman "volume export my-vol : cat '${TEST_DIR}/vol.tar'"

  run podman_volume_export_untar_stdout my-vol myfile.txt
  assert_success
  assert_output --partial "hello-content"

  unstub podman
}

@test "sourcing podman-volume.sh sets its double-inclusion guard" {
  source hack/lib/podman/podman-volume.sh
  [[ "${__hack_lib_podman_volume_sourced}" == true ]]
}
