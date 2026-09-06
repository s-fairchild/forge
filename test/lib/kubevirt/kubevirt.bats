#!/usr/bin/env bats
#
# Tests for hack/lib/kubevirt/kubevirt.sh.
#
# See test/test_helper.bash's "IMPORTANT" comment: each @test sources the file under test as
# its own first line, never in setup().
#
# kubectl is mocked via bats-mock; this file's own `kubectl apply -k`/`kubectl wait` calls are
# the only external side effects it has.

load "${PWD}/test/test_helper"

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "kubevirt_install applies the operator and CR, waiting on both" {
  source hack/lib/kubevirt/kubevirt.sh
  stub kubectl \
    "apply -k pkg/operators/kubevirt/overlays/staging : exit 0" \
    "wait deployment/virt-operator -n kubevirt --for=condition=Available --timeout=300s : exit 0" \
    "wait kv/kubevirt -n kubevirt --for=condition=Available --timeout=300s : exit 0"

  run kubevirt_install
  assert_success

  unstub kubectl
}

@test "kubevirt_install fails via fatal when the operator kustomization apply fails" {
  source hack/lib/kubevirt/kubevirt.sh
  stub kubectl "apply -k pkg/operators/kubevirt/overlays/staging : exit 1"

  run kubevirt_install
  assert_failure
  assert_output --partial "failed to apply pkg/operators/kubevirt/overlays/staging"

  unstub kubectl
}

@test "kubevirt_install fails via fatal when virt-operator does not become Available" {
  source hack/lib/kubevirt/kubevirt.sh
  stub kubectl \
    "apply -k pkg/operators/kubevirt/overlays/staging : exit 0" \
    "wait deployment/virt-operator * : exit 1"

  run kubevirt_install
  assert_failure
  assert_output --partial "virt-operator did not become Available"

  unstub kubectl
}

@test "kubevirt_install fails via fatal when the KubeVirt CR does not become Available" {
  source hack/lib/kubevirt/kubevirt.sh
  stub kubectl \
    "apply -k pkg/operators/kubevirt/overlays/staging : exit 0" \
    "wait deployment/virt-operator * : exit 0" \
    "wait kv/kubevirt * : exit 1"

  run kubevirt_install
  assert_failure
  assert_output --partial "KubeVirt CR did not become Available"

  unstub kubectl
}

@test "cdi_install applies the operator and CR, waiting on both" {
  source hack/lib/kubevirt/kubevirt.sh
  stub kubectl \
    "apply -k pkg/operators/cdi/overlays/staging : exit 0" \
    "wait deployment/cdi-operator -n cdi --for=condition=Available --timeout=300s : exit 0" \
    "wait cdi/cdi --for=condition=Available --timeout=300s : exit 0"

  run cdi_install
  assert_success

  unstub kubectl
}

@test "cdi_install fails via fatal when the operator kustomization apply fails" {
  source hack/lib/kubevirt/kubevirt.sh
  stub kubectl "apply -k pkg/operators/cdi/overlays/staging : exit 1"

  run cdi_install
  assert_failure
  assert_output --partial "failed to apply pkg/operators/cdi/overlays/staging"

  unstub kubectl
}

@test "cdi_install fails via fatal when cdi-operator does not become Available" {
  source hack/lib/kubevirt/kubevirt.sh
  stub kubectl \
    "apply -k pkg/operators/cdi/overlays/staging : exit 0" \
    "wait deployment/cdi-operator * : exit 1"

  run cdi_install
  assert_failure
  assert_output --partial "cdi-operator did not become Available"

  unstub kubectl
}

@test "cdi_install fails via fatal when the CDI CR does not become Available (regression: polarity bug)" {
  # Regression test for a real bug fixed during the style rewrite: this wait's condition was
  # previously inverted (`if kubectl wait ...; then fatal ...`), so it called fatal on SUCCESS
  # and silently swallowed a real failure -- the opposite of every other check in this file. If
  # that polarity regresses, this test fails because `cdi_install` would wrongly report success
  # here despite the stubbed `kubectl wait cdi/cdi` failing.
  source hack/lib/kubevirt/kubevirt.sh
  stub kubectl \
    "apply -k pkg/operators/cdi/overlays/staging : exit 0" \
    "wait deployment/cdi-operator * : exit 0" \
    "wait cdi/cdi * : exit 1"

  run cdi_install
  assert_failure
  assert_output --partial "CDI CR did not become Available"

  unstub kubectl
}

@test "the double-inclusion guard variable is set after sourcing" {
  source hack/lib/kubevirt/kubevirt.sh
  [[ "${__hack_lib_kubevirt_sourced}" == true ]]
}
