#!/usr/bin/env bats
#
# Tests for hack/lib/podman/podman.sh (the podman-container/podman-secret/podman-volume
# umbrella loader).
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

@test "sourcing podman.sh pulls in podman-container.sh, podman-secret.sh, and podman-volume.sh" {
  run bash -c '
    source hack/lib/podman/podman.sh
    declare -F podman_container > /dev/null &&
    declare -F podman_secret_create_replace_from_stdin > /dev/null &&
    declare -F podman_secret_showsecret > /dev/null &&
    declare -F podman_secret_create_from_file > /dev/null &&
    declare -F podman_secret_gen_file_secretsdata > /dev/null &&
    declare -F podman_secret_filter_by_label > /dev/null &&
    declare -F podman_volume_exists > /dev/null &&
    declare -F podman_volume_create > /dev/null &&
    declare -F podman_volume_export_untar_stdout > /dev/null
  '
  assert_success
}

@test "sourcing podman.sh sets its own and all three sub-files' double-inclusion guards" {
  run bash -c '
    source hack/lib/podman/podman.sh
    [[ "${__hack_lib_podman_sourced}" == true ]] &&
    [[ "${__hack_lib_podman_container_sourced}" == true ]] &&
    [[ "${__hack_lib_podman_secret_sourced}" == true ]] &&
    [[ "${__hack_lib_podman_volume_sourced}" == true ]]
  '
  assert_success
}

@test "the real adapter.sh fatal() wins over podman.sh's own fallback definition" {
  # podman.sh defines a fallback `fatal()` only if one isn't already defined, so that it (and the
  # 3 files it loads) can be sourced standalone without adapter.sh -- but once the sub-files pull
  # in the real adapter.sh (for debug/error/etc.), its real fatal() should take over.
  run bash -c '
    source hack/lib/podman/podman.sh
    fatal --status=42 "boom" 2>/dev/null
  '
  assert_failure 42
}

@test "sourcing podman.sh twice does not redefine already-guarded sub-files" {
  run bash -c '
    source hack/lib/podman/podman.sh
    source hack/lib/podman/podman.sh
    declare -F podman_container > /dev/null
  '
  assert_success
}
