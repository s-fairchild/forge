#!/usr/bin/env bats
#
# Tests for hack/bin/generate-kustomize.sh.

load "${PWD}/test/test_helper"

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "fails when the base directory operand is missing" {
  run hack/bin/generate-kustomize.sh
  assert_failure
  assert_output --partial '$1'
}

@test "fails when the overlay operand is missing" {
  run hack/bin/generate-kustomize.sh "${TEST_DIR}/pkg" "${TEST_DIR}/out"
  assert_failure
  assert_output --partial '$3'
}

@test "fails when no overlay directories are found" {
  mkdir -p "${TEST_DIR}/pkg"
  run hack/bin/generate-kustomize.sh "${TEST_DIR}/pkg" "${TEST_DIR}/out" prod
  assert_failure
  assert_output --partial "No overlays were found"
}

@test "builds an enabled app's overlay with kustomize and writes its manifest" {
  # jellyfin is one of the apps_enabled entries in hack/etc/kube-manifests-gen.env.
  mkdir -p "${TEST_DIR}/pkg/workloads/jellyfin/overlays/prod"
  stub kustomize "build * : echo 'apiVersion: v1'"

  run hack/bin/generate-kustomize.sh "${TEST_DIR}/pkg" "${TEST_DIR}/out" prod
  assert_success
  assert_file_exists "${TEST_DIR}/out/jellyfin.yaml"
  assert_file_contains "${TEST_DIR}/out/jellyfin.yaml" "apiVersion: v1"

  unstub kustomize
}

@test "skips an app that is not in apps_enabled" {
  # pihole exists under pkg/workloads/ in the real repo but is commented out of apps_enabled.
  mkdir -p "${TEST_DIR}/pkg/workloads/pihole/overlays/prod"

  run hack/bin/generate-kustomize.sh "${TEST_DIR}/pkg" "${TEST_DIR}/out" prod
  assert_success
  assert_file_not_exists "${TEST_DIR}/out/pihole.yaml"
}
