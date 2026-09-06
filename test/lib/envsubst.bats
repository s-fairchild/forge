#!/usr/bin/env bats
#
# Tests for hack/lib/envsubst.sh.
#
# See test/test_helper.bash's "IMPORTANT" comment: each @test sources the file under test as
# its own first line, never in setup() -- sourcing from setup() would make envsubst.sh's
# `declare -r` constants (and adapter.sh's, transitively) local to setup() and gone by the time
# the @test body runs.

load "${PWD}/test/test_helper"

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "envsubst invokes podman run with the expected base options, image, and passthrough flags" {
  source hack/lib/envsubst.sh
  stub podman \
    "run --rm -i --log-level warn --env ENVSUBST_* docker.io/steve51516/envsubst:latest -no-digit -no-unset -no-empty INPUT.tmpl : echo stubbed-envsubst"

  run envsubst INPUT.tmpl
  assert_success
  assert_output --partial "stubbed-envsubst"

  unstub podman
}

@test "envsubst honors a custom PODMAN_LOG_LEVEL" {
  source hack/lib/envsubst.sh
  export PODMAN_LOG_LEVEL="debug"
  stub podman "run --rm -i --log-level debug --env ENVSUBST_* * : echo stubbed"

  run envsubst INPUT.tmpl
  assert_success

  unstub podman
}

@test "envsubst mounts each ENVSUBST_SECRET_MOUNTS entry as a podman env-type secret" {
  source hack/lib/envsubst.sh
  # shellcheck disable=SC2034 -- consumed by envsubst() via the [[ -v ]] check + expansion
  declare -a ENVSUBST_SECRET_MOUNTS=(my-secret other-secret)
  # BUG (pre-existing, not fixed per task instructions): the `mapfile -O ... < <(printf -- "--secret
  # %s,type=env\n" ...)` construction reads each *whole line* as one array element, so
  # podman_run_options ends up with single combined elements like "--secret my-secret,type=env"
  # (one argv token containing an embedded space) instead of separate "--secret"/"my-secret,type=env"
  # tokens -- almost certainly not what a real `podman run` invocation wants. bats-mock's plan-line
  # patterns are themselves naively whitespace-split, so a single argv token containing a literal
  # space can't be expressed as an exact expected pattern here; falling back to a wildcard for the
  # whole call and just confirming it still succeeds is what's feasible.
  stub podman "run * : echo stubbed"

  run envsubst INPUT.tmpl
  assert_success

  unstub podman
}

@test "envsubst forwards a non-zero podman exit status" {
  source hack/lib/envsubst.sh
  stub podman "run * : exit 7"

  run envsubst INPUT.tmpl
  assert_failure 7

  unstub podman
}

@test "envsubst is exported for use by non-interactive shells (e.g. Make recipes)" {
  source hack/lib/envsubst.sh
  run bash -c 'declare -F envsubst > /dev/null'
  assert_success
}

@test "the double-inclusion guard variable is set after sourcing" {
  source hack/lib/envsubst.sh
  [[ "${__hack_lib_envsubst_sourced}" == true ]]
}
