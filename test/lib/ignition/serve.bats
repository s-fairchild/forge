#!/usr/bin/env bats
#
# Tests for hack/lib/ignition/serve.sh.
#
# See test/test_helper.bash's "IMPORTANT" comment: each @test sources the file under test as
# its own first line, never in setup() -- sourcing from setup() would make serve.sh's
# `declare -r` constants local to setup() and gone by the time the @test body runs.
#
# NOTE on two real bugs in serve() discovered while writing these tests (not fixed here, per
# instructions -- tests below assert the CURRENT, buggy behavior):
#
#   1. The getopts spec is `':i:s:d:e:h:c:k:'` -- `h:` gives -h a *required* argument, so a
#      bare `-h` with nothing after it hits the `:` (missing-argument) branch instead of the
#      intended `h)` usage-and-exit-0 branch, and `-h` followed by any other token (even one
#      that looks like another flag, e.g. `-c`) silently swallows that token as its own OPTARG
#      instead of parsing it as a separate option.
#   2. The `i`/`c`/`k` case branches call `is_option_arg_dup "${opt}" "${OPTARG}"` -- passing
#      the just-parsed OPTARG (always non-empty) instead of the target variable's
#      *pre-assignment* value (the documented calling convention, see
#      hack/vendor/bashkit/local/lib/bashkit/options-operands-utils.sh). Since OPTARG is always
#      non-empty here, is_option_arg_dup treats the very first use of -i/-c/-k as a duplicate
#      and always returns 1 -- serve() can never actually reach the podman invocation, since
#      -c and -k are mandatory and both are broken this way.

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

@test "serve -c triggers the is_option_arg_dup bug and never reaches the -k check" {
  # Documents bug #2 above: the very first -c use is misreported as a duplicate, so the
  # intended "-k missing" fatal path (which would only be reached after a working -c) is
  # actually unreachable through the public serve() interface as currently written.
  source hack/lib/ignition/serve.sh
  run serve -c my-cert
  assert_failure
  assert_output --partial "can only be specified once"
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
