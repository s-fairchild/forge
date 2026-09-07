#!/usr/bin/env bats
#
# Tests for hack/lib/ignition/serve.sh.
#
# See test/test_helper.bash's "IMPORTANT" comment: each @test sources the file under test as
# its own first line, never in setup() -- sourcing from setup() would make serve.sh's
# `declare -r` constants local to setup() and gone by the time the @test body runs.
#
# NOTE on a real bug in serve() discovered while writing these tests (not fixed here, per
# instructions -- tests below assert the CURRENT, buggy behavior):
#
#   1. The getopts spec is `':i:s:d:e:h:c:k:'` -- `h:` gives -h a *required* argument, so a
#      bare `-h` with nothing after it hits the `:` (missing-argument) branch instead of the
#      intended `h)` usage-and-exit-0 branch, and `-h` followed by any other token (even one
#      that looks like another flag, e.g. `-c`) silently swallows that token as its own OPTARG
#      instead of parsing it as a separate option.
#
# A second bug this file used to document -- the `i`/`c`/`k` case branches passing the
# just-parsed OPTARG instead of the target variable's pre-assignment value to
# core::is_option_arg_dup, which misreported the first use of -i/-c/-k as a duplicate -- has
# since been fixed in serve.sh; see the regression test below instead of a bug note.

load "${PWD}/test/test_helper"

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "usage_serve prints usage to stderr" {
  source hack/lib/ignition/serve.sh
  run usage_serve
  assert_success
  assert_output --partial "Usage: serve"
}

@test "serve rejects an unknown option" {
  source hack/lib/ignition/serve.sh
  run serve -z
  assert_failure
  assert_output --partial "is unknown"
}

@test "serve fails when -c is missing" {
  source hack/lib/ignition/serve.sh
  run serve
  assert_failure
  assert_output --partial "-c"
  assert_output --partial "must be provided"
}

@test "serve -c does not falsely trigger is_option_arg_dup, reaching the -k check" {
  # Regression test: core::is_option_arg_dup is called with the target variable's
  # pre-assignment value, so a single -c is not misreported as a duplicate -- serve()
  # proceeds past -c and correctly fails on the still-missing -k.
  source hack/lib/ignition/serve.sh
  run serve -c my-cert
  assert_failure
  assert_output --partial "-k"
  assert_output --partial "must be provided"
}

@test "a bare -h fails instead of printing usage, due to the getopts spec bug" {
  # Documents bug #1 above: 'h:' in the getopts spec means a bare -h with nothing following it
  # hits the missing-argument branch, not the intended h) usage/return-0 branch.
  source hack/lib/ignition/serve.sh
  run serve -h
  assert_failure
  assert_output --partial "-h"
  assert_output --partial "must be provided"
}

@test "-h swallows the following token as its own argument, due to the getopts spec bug" {
  # Documents bug #1 above: -h followed by another token (even one shaped like another flag)
  # consumes it as OPTARG instead of parsing it separately -- so this "succeeds" only because
  # -c was never actually parsed as its own option.
  source hack/lib/ignition/serve.sh
  run serve -h -c my-cert
  assert_success
  assert_output --partial "Usage: serve"
}

@test "the double-inclusion guard variable lets a caller skip re-sourcing" {
  # The __hack_lib_ignition_serve_sourced guard is a contract for CALLERS (they check it before
  # sourcing this file), not self-protection against being sourced twice directly -- this file
  # has no internal guard around its own body, so a raw double `source` (bypassing that
  # caller-side check) hits bash's readonly-redeclaration error on its own top-of-file
  # constants. Verify the guard variable is set to "true" after one source, which is what
  # callers actually rely on. This spawns its own bash process, so it's unaffected by the
  # setup()-scoping gotcha described above.
  source hack/lib/ignition/serve.sh
  [[ "${__hack_lib_ignition_serve_sourced}" == true ]]
}
