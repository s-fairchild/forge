#!/usr/bin/env bats
#
# Tests for hack/bin/k3d-cluster-down.sh.

load "${PWD}/test/test_helper"

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "-h prints usage and exits 0" {
  run hack/bin/k3d-cluster-down.sh -h
  assert_success
  assert_output --partial "Usage: k3d-cluster-down.sh"
}

@test "fails when -f is missing" {
  run hack/bin/k3d-cluster-down.sh
  assert_failure
  assert_output --partial "-f"
}

@test "fails when the config file does not exist" {
  # -v overrides common_setup's QUIET=1 (CLI flag beats env var) so the fatal
  # message actually reaches console output for the assertion below.
  run hack/bin/k3d-cluster-down.sh -v -f "${TEST_DIR}/missing.yaml"
  assert_failure
  assert_output --partial "file not found"
}

@test "fails when the config has no .metadata.name" {
  local -r config="${TEST_DIR}/staging.yaml"
  printf 'apiVersion: k3d.io/v1alpha5\nkind: Simple\n' > "${config}"
  # .metadata.name is read via the yq() shell function (hack/lib/yq.sh), which itself shells
  # out to `podman run ... mikefarah/yq`, not a plain `yq` binary on PATH -- stub podman instead
  # (without this stub the real containerized yq would run against a path it can't see, since
  # only $PWD is bind-mounted into it -- never let this hit a real container).
  stub podman "run * : echo null"

  run hack/bin/k3d-cluster-down.sh -v -f "${config}"
  assert_failure
  assert_output --partial "no .metadata.name"

  unstub podman
}

@test "warns and no-ops when the cluster does not exist" {
  local -r config="${TEST_DIR}/staging.yaml"
  printf 'apiVersion: k3d.io/v1alpha5\nkind: Simple\nmetadata:\n  name: kubevirt-staging\n' > "${config}"
  stub podman "run * : echo kubevirt-staging"
  stub k3d "cluster list kubevirt-staging : exit 1"

  run hack/bin/k3d-cluster-down.sh -v -f "${config}"
  assert_success
  assert_output --partial "does not exist; nothing to delete"

  unstub k3d
  unstub podman
}

@test "deletes the cluster when it exists" {
  local -r config="${TEST_DIR}/staging.yaml"
  printf 'apiVersion: k3d.io/v1alpha5\nkind: Simple\nmetadata:\n  name: kubevirt-staging\n' > "${config}"
  stub podman "run * : echo kubevirt-staging"
  stub k3d \
    "cluster list kubevirt-staging : exit 0" \
    "cluster delete kubevirt-staging : echo deleted"

  run hack/bin/k3d-cluster-down.sh -v -f "${config}"
  assert_success
  assert_output --partial "Deleting k3d cluster"

  unstub k3d
  unstub podman
}

@test "fails and reports when k3d cluster delete fails" {
  local -r config="${TEST_DIR}/staging.yaml"
  printf 'apiVersion: k3d.io/v1alpha5\nkind: Simple\nmetadata:\n  name: kubevirt-staging\n' > "${config}"
  stub podman "run * : echo kubevirt-staging"
  stub k3d \
    "cluster list kubevirt-staging : exit 0" \
    "cluster delete kubevirt-staging : exit 1"

  run hack/bin/k3d-cluster-down.sh -v -f "${config}"
  assert_failure
  assert_output --partial "k3d cluster delete failed"

  unstub k3d
  unstub podman
}

@test "rejects an unknown option" {
  run hack/bin/k3d-cluster-down.sh -v -z
  assert_failure
  assert_output --partial "is unknown"
}
