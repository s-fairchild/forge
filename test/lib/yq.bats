#!/usr/bin/env bats
#
# Tests for hack/lib/yq.sh.
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

@test "yq invokes podman run with the expected base options, workdir mount, image, and passthrough args" {
  source hack/lib/yq.sh
  stub podman \
    "run --userns keep-id --env YQ_* --log-level warn -i --rm -v ${REPO_ROOT}:/workdir:O --workdir /workdir docker.io/mikefarah/yq:4.53.2 --exit-status=1 .foo config.yaml : echo '{\"foo\":\"bar\"}'"

  run yq .foo config.yaml
  assert_success
  assert_output --partial '{"foo":"bar"}'

  unstub podman
}

@test "yq honors a custom PODMAN_LOG_LEVEL" {
  source hack/lib/yq.sh
  export PODMAN_LOG_LEVEL="debug"
  stub podman "run --userns keep-id --env YQ_* --log-level debug * : echo stubbed"

  run yq .foo config.yaml
  assert_success

  unstub podman
}

@test "yq forwards a non-zero podman exit status" {
  source hack/lib/yq.sh
  stub podman "run * : exit 2"

  run yq .foo config.yaml
  assert_failure 2

  unstub podman
}

@test "yq's own debug trace goes to stderr, not stdout, so command substitution stays clean" {
  source hack/lib/yq.sh
  stub podman "run * : echo clean-value"

  # Deliberately NOT using bats' `run` here -- this exercises the exact real-world usage pattern
  # (`result=\"\$(yq ...)\"`) that yq()'s doc comment says must stay uncorrupted by its own
  # trace log, capturing only stdout the way a real caller would.
  result="$(yq .foo config.yaml 2> /dev/null)"
  assert_equal "${result}" "clean-value"

  unstub podman
}

@test "the double-inclusion guard variable is set after sourcing" {
  source hack/lib/yq.sh
  [[ "${__hack_lib_yq_sourced}" == true ]]
}
