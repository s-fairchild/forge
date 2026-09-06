#!/usr/bin/env bats
#
# Tests for hack/bin/k3d-cluster-up.sh.

load "${PWD}/test/test_helper"

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# stub_kubevirt_cdi_install_success()
#
# Stubs kubectl for a fully successful kubevirt_install()+cdi_install() chain (6 kubectl calls:
# apply+2 waits per install). Call `unstub kubectl` when done.
stub_kubevirt_cdi_install_success() {
  stub_repeated kubectl \
    "apply -k pkg/operators/kubevirt/overlays/staging : exit 0" \
    "wait deployment/virt-operator * : exit 0" \
    "wait kv/kubevirt * : exit 0" \
    "apply -k pkg/operators/cdi/overlays/staging : exit 0" \
    "wait deployment/cdi-operator * : exit 0" \
    "wait cdi/cdi * : exit 0"
}

@test "-h prints usage and exits 0" {
  run hack/bin/k3d-cluster-up.sh -h
  assert_success
  assert_output --partial "Usage: k3d-cluster-up.sh"
}

@test "fails when -f is missing" {
  run hack/bin/k3d-cluster-up.sh
  assert_failure
  assert_output --partial "-f"
}

@test "fails when the config file does not exist" {
  run hack/bin/k3d-cluster-up.sh -v -f "${TEST_DIR}/missing.yaml"
  assert_failure
  assert_output --partial "file not found"
}

@test "fails when the config has no .metadata.name" {
  local -r config="${TEST_DIR}/staging.yaml"
  printf 'apiVersion: k3d.io/v1alpha5\nkind: Simple\n' > "${config}"
  stub podman "run * : echo null"

  run hack/bin/k3d-cluster-up.sh -v -f "${config}"
  assert_failure
  assert_output --partial "no .metadata.name"

  unstub podman
}

@test "creates the cluster when it does not exist, then installs KubeVirt and CDI" {
  local -r config="${TEST_DIR}/staging.yaml"
  printf 'apiVersion: k3d.io/v1alpha5\nkind: Simple\nmetadata:\n  name: kubevirt-staging\n' > "${config}"
  stub podman "run * : echo kubevirt-staging"
  stub k3d \
    "cluster list kubevirt-staging : exit 1" \
    "cluster create --config ${config} : echo created"
  stub_kubevirt_cdi_install_success

  run hack/bin/k3d-cluster-up.sh -v -f "${config}"
  assert_success
  assert_output --partial "Creating k3d cluster"

  unstub k3d
  unstub podman
}

@test "skips creation and installs KubeVirt/CDI when the cluster already exists" {
  local -r config="${TEST_DIR}/staging.yaml"
  printf 'apiVersion: k3d.io/v1alpha5\nkind: Simple\nmetadata:\n  name: kubevirt-staging\n' > "${config}"
  stub podman "run * : echo kubevirt-staging"
  stub k3d "cluster list kubevirt-staging : exit 0"
  stub_kubevirt_cdi_install_success

  run hack/bin/k3d-cluster-up.sh -v -f "${config}"
  assert_success
  assert_output --partial "already exists"
  refute_output --partial "cluster create"

  unstub k3d
  unstub podman
}

@test "fails and reports when k3d cluster create fails" {
  local -r config="${TEST_DIR}/staging.yaml"
  printf 'apiVersion: k3d.io/v1alpha5\nkind: Simple\nmetadata:\n  name: kubevirt-staging\n' > "${config}"
  stub podman "run * : echo kubevirt-staging"
  stub k3d \
    "cluster list kubevirt-staging : exit 1" \
    "cluster create --config ${config} : exit 1"

  run hack/bin/k3d-cluster-up.sh -v -f "${config}"
  assert_failure
  assert_output --partial "k3d cluster create failed"

  unstub k3d
  unstub podman
}

@test "rejects an unknown option" {
  run hack/bin/k3d-cluster-up.sh -v -z
  assert_failure
  assert_output --partial "is unknown"
}
