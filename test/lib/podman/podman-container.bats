#!/usr/bin/env bats
#
# Tests for hack/lib/podman/podman-container.sh.
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

@test "podman_container invokes the nested podman with the expected fixed options and passthrough args" {
  source hack/lib/podman/podman-container.sh
  stub podman \
    "run --user=podman --security-opt=label=disable --volume=graphroot-user-podman:/home/podman/.local/share/containers/storage --rm -i registry.redhat.io/ubi10/podman:latest podman secret ls : echo stubbed-nested-podman"

  run podman_container secret ls
  assert_success
  assert_output --partial "stubbed-nested-podman"

  unstub podman
}

@test "podman_container forwards a non-zero exit status from the nested podman" {
  source hack/lib/podman/podman-container.sh
  stub podman "run * : exit 7"

  run podman_container secret ls
  assert_failure 7

  unstub podman
}

@test "sourcing podman-container.sh sets its double-inclusion guard" {
  source hack/lib/podman/podman-container.sh
  [[ "${__hack_lib_podman_container_sourced}" == true ]]
}
