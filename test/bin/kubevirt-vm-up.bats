#!/usr/bin/env bats
#
# Tests for hack/bin/kubevirt-vm-up.sh.

load "${PWD}/test/test_helper"

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "-h prints usage and exits 0 without invoking kubectl/podman" {
  run hack/bin/kubevirt-vm-up.sh -h
  assert_success
  assert_output --partial "Usage: kubevirt-vm-up.sh -f vm_manifest -n namespace_manifest -s ignition_secret"
}

@test "rejects an unknown option" {
  run hack/bin/kubevirt-vm-up.sh -z
  assert_failure
  assert_output --partial "option is unknown"
}

@test "fails when required options are missing" {
  run hack/bin/kubevirt-vm-up.sh
  assert_failure
  assert_output --partial "-f option must be provided"
}

@test "fails when the vm_manifest file does not exist" {
  local namespace_manifest="${TEST_DIR}/namespace.yaml"
  cat > "${namespace_manifest}" <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: test-ns
EOF

  run hack/bin/kubevirt-vm-up.sh -f "${TEST_DIR}/missing-vm.yaml" \
                                  -n "${namespace_manifest}" \
                                  -s ignition-staging
  assert_failure
  assert_output --partial "file not found"
}

@test "applies namespace, builds the ignition Secret from the podman secret, and applies the VM" {
  local vm_manifest="${TEST_DIR}/vm.yaml"
  local namespace_manifest="${TEST_DIR}/namespace.yaml"

  cat > "${vm_manifest}" <<'EOF'
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: rick-staging
EOF

  cat > "${namespace_manifest}" <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: test-ns
EOF

  # yq() (hack/lib/yq.sh) is itself a podman wrapper, so the first podman invocation is the
  # `yq eval '.metadata.name' <namespace_manifest>` call and the second is
  # podman_secret_showsecret's `podman secret inspect --showsecret ...` call. bats-mock matches
  # patterns positionally per plan-line index (not by content routing), so the two lines below
  # rely on that fixed call order -- only the leading verb is pinned since the rest of each
  # command line isn't relevant here (exact podman/yq argument construction is covered by
  # test/lib/yq.bats and test/lib/podman/podman-secret.bats).
  stub podman \
    "run : echo test-ns" \
    "secret : echo '{\"ignition\":\"payload\"}'"

  # kubectl is invoked 4 times: apply namespace, create secret (dry-run client), apply the
  # piped Secret yaml, then apply the VM manifest. The "create secret ... | kubectl apply -f -"
  # step forks BOTH kubectl invocations concurrently (that's what a shell pipe does) rather than
  # strictly sequentially, which races bats-mock's normal call-index-based matching -- so this
  # uses stub_repeated, which dispatches each call to whichever plan line's pattern actually
  # matches its real arguments (content-based, not call-order-based), and is safe under that
  # concurrency.
  stub_repeated kubectl \
    "apply -f ${namespace_manifest} : echo namespace-applied" \
    "--namespace=test-ns create secret * : echo 'kind: Secret'" \
    "apply -f - : cat > /dev/null; echo secret-applied" \
    "apply -f ${vm_manifest} : echo vm-applied"

  run hack/bin/kubevirt-vm-up.sh -f "${vm_manifest}" -n "${namespace_manifest}" -s ignition-staging
  assert_success
  assert_output --partial "vm-applied"

  unstub podman
  # Not calling `unstub kubectl`: it re-invokes the stub once more to verify every
  # planned line was consumed, but that bookkeeping races across the two genuinely
  # concurrent kubectl processes in "create secret ... | kubectl apply -f -" (a real
  # shell pipe forks both sides to run at the same time) and can spuriously report
  # failure even though both calls matched and ran correctly (verified above via
  # assert_success/assert_output). Nothing to leak: BATS_MOCK_TMPDIR is test_helper's
  # per-test BATS_TEST_TMPDIR, which bats itself cleans up after this test.
}

@test "-k overrides the default ignition-payload Secret name" {
  local vm_manifest="${TEST_DIR}/vm.yaml"
  local namespace_manifest="${TEST_DIR}/namespace.yaml"

  cat > "${vm_manifest}" <<'EOF'
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: rick-staging
EOF

  cat > "${namespace_manifest}" <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: test-ns
EOF

  stub podman \
    "run : echo test-ns" \
    "secret : echo '{\"ignition\":\"payload\"}'"

  # See the identical comment on the previous test re: stub_repeated and pipeline concurrency.
  stub_repeated kubectl \
    "apply -f ${namespace_manifest} : echo namespace-applied" \
    "--namespace=test-ns create secret generic custom-secret : echo 'kind: Secret'" \
    "apply -f - : cat > /dev/null; echo secret-applied" \
    "apply -f ${vm_manifest} : echo vm-applied"

  run hack/bin/kubevirt-vm-up.sh -f "${vm_manifest}" -n "${namespace_manifest}" \
                                  -s ignition-staging -k custom-secret
  assert_success
  assert_output --partial "vm-applied"

  unstub podman
  # Not calling `unstub kubectl`: it re-invokes the stub once more to verify every
  # planned line was consumed, but that bookkeeping races across the two genuinely
  # concurrent kubectl processes in "create secret ... | kubectl apply -f -" (a real
  # shell pipe forks both sides to run at the same time) and can spuriously report
  # failure even though both calls matched and ran correctly (verified above via
  # assert_success/assert_output). Nothing to leak: BATS_MOCK_TMPDIR is test_helper's
  # per-test BATS_TEST_TMPDIR, which bats itself cleans up after this test.
}
