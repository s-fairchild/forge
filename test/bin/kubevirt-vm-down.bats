#!/usr/bin/env bats
#
# Tests for hack/bin/kubevirt-vm-down.sh.

load "${PWD}/test/test_helper"

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "-h prints usage and exits 0 without invoking kubectl" {
  run hack/bin/kubevirt-vm-down.sh -h
  assert_success
  assert_output --partial "Usage: kubevirt-vm-down.sh -f vm_manifest"
}

@test "rejects an unknown option" {
  run hack/bin/kubevirt-vm-down.sh -z
  assert_failure
  assert_output --partial "option is unknown"
}

@test "fails when -f is missing" {
  run hack/bin/kubevirt-vm-down.sh
  assert_failure
  assert_output --partial "-f option must be provided"
}

@test "fails when the vm_manifest file does not exist" {
  run hack/bin/kubevirt-vm-down.sh -f "${TEST_DIR}/missing.yaml"
  assert_failure
  assert_output --partial "file not found"
}

@test "deletes the given VirtualMachine manifest via kubectl" {
  local manifest="${TEST_DIR}/vm.yaml"
  cat > "${manifest}" <<'EOF'
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: rick-staging
EOF

  stub kubectl "delete -f ${manifest} --ignore-not-found : echo deleted-ok"

  run hack/bin/kubevirt-vm-down.sh -f "${manifest}"
  assert_success
  assert_output --partial "deleted-ok"

  unstub kubectl
}

@test "propagates a kubectl delete failure" {
  local manifest="${TEST_DIR}/vm.yaml"
  cat > "${manifest}" <<'EOF'
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: rick-staging
EOF

  stub kubectl "delete -f ${manifest} --ignore-not-found : exit 1"

  run hack/bin/kubevirt-vm-down.sh -f "${manifest}"
  assert_failure
  assert_output --partial "kubectl delete -f ${manifest} failed"

  unstub kubectl
}
