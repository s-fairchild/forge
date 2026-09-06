#!/usr/bin/env bats
#
# Tests for hack/bin/podman-build.sh.
#
# Real usage (see pkg/containers/Makefile) always calls this with a single argument -- the
# build context directory -- e.g. `hack/bin/podman-build.sh pkg/containers/ffmpeg`. That's the
# only calling convention exercised here: build_context_get's `opts[0]` vs. `unset opts[-1]`
# split (see test/lib/podman/build_multi_stage.bats) only diverges with 2+ arguments, and the
# TODO in podman-build.sh's own main() acknowledges multi-option support isn't wired up yet.

load "${PWD}/test/test_helper"

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "builds the image named after the context directory's basename" {
  # load_podman_build_env() looks up hack/env/podman/build/<basename>.env by the context
  # directory's basename (see build_multi_stage.sh) -- that path isn't overridable (a `declare
  # -r` computed from $PWD), so the context dir here must be named after one of the real,
  # already-checked-in .env fixtures. Using libcamera.env specifically, not example.env (which
  # test/lib/podman/build_multi_stage.bats uses without `set -o nounset` active): example.env
  # references MOTION_VERSION_TAG_DEFAULT without ever defining it, which is silently harmless
  # under plain bash but a hard "unbound variable" error under this entrypoint's own
  # `set -o nounset` -- a pre-existing bug in that fixture, not fixed here.
  mkdir -p "${TEST_DIR}/libcamera"
  touch "${TEST_DIR}/libcamera/Containerfile"
  stub podman "build * : echo built"

  run hack/bin/podman-build.sh "${TEST_DIR}/libcamera"
  assert_success
  assert_output --partial "Complete."

  unstub podman
}

@test "fails when the context directory does not exist" {
  run hack/bin/podman-build.sh "${TEST_DIR}/no-such-dir"
  assert_failure
  assert_output --partial "Context directory not found"
}

@test "propagates a non-zero podman build exit status" {
  mkdir -p "${TEST_DIR}/libcamera"
  touch "${TEST_DIR}/libcamera/Containerfile"
  stub podman "build * : exit 3"

  run hack/bin/podman-build.sh "${TEST_DIR}/libcamera"
  assert_failure 3

  unstub podman
}
