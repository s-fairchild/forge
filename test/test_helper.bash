# test/test_helper.bash
#
# Shared bats setup for the hack/ test suite. Every .bats file loads this via
# `load "${PWD}/test/test_helper"` — that only resolves correctly when bats is invoked from the
# repo root (as `make test`/`make coverage` do), matching this repo's "run from repo root"
# convention for hack/lib and hack/bin (see CLAUDE.md).
#
# Tests for hack/bin/<name>.sh go in test/bin/<name>.bats, and tests for hack/lib/<dir>/<file>.sh
# in test/lib/<dir>/<file>.bats. `make test` runs every .bats file under both directories. See the
# end of this file for how to load what each kind of test exercises.

REPO_ROOT="$(pwd)"
export REPO_ROOT

load "${REPO_ROOT}/test/vendor/bats-support/load"
load "${REPO_ROOT}/test/vendor/bats-assert/load"
load "${REPO_ROOT}/test/vendor/bats-file/load"
load "${REPO_ROOT}/test/vendor/bats-mock/stub"

# bats-mock's stub.bash hardcodes its state directory as `BATS_MOCK_TMPDIR="${BATS_TMPDIR}"` --
# and BATS_TMPDIR is bats' one GLOBAL scratch dir (defaults to plain "$TMPDIR"/"/tmp"), shared by
# every test in the run, not per-test. Two tests that both `stub podman` -- whether sequentially
# (one leaves stale plan/run state behind if it doesn't reach its own `unstub`) or concurrently
# under `--jobs N` (two tests genuinely racing on the same "podman-stub-plan"/"podman-stub-run"
# files at once) -- corrupt each other's call-index-based matching. Re-point it at
# BATS_TEST_TMPDIR (bats' own per-test scratch dir, unique even across parallel jobs) and redo
# the PATH prepend stub.bash already did against the now-stale BATS_MOCK_BINDIR.
if [[ -n "${BATS_TEST_TMPDIR:-}" ]]; then
  BATS_MOCK_TMPDIR="${BATS_TEST_TMPDIR}"
  BATS_MOCK_BINDIR="${BATS_MOCK_TMPDIR}/bin"
  PATH="${BATS_MOCK_BINDIR}:${PATH}"
fi

# common_setup()
#
# Call from every .bats file's setup(). Ensures cwd is the repo root (the scripts under test read
# pkg/, hack/etc/ and deploy/ relative to it) and creates a fresh scratch directory
# for the test to use instead of touching /tmp directly, keeping parallel bats jobs isolated
# from each other.
#
# Globals:
#   REPO_ROOT   Set above.
# Outputs:
#   Exports TEST_DIR, a fresh mktemp -d directory.
common_setup() {
  cd "${REPO_ROOT}" || return 1
  TEST_DIR="$(mktemp -d "${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/forge-test.XXXXXX")"
  export TEST_DIR
  # The scripts under test log through bashkit, which picks its bash-logger config from
  # BASHKIT_ENV. Pin it, so that a developer's own value doesn't apply: the prod config logs to
  # the journal, and journald broadcasts the emergency level log_fatal uses to every terminal.
  export BASHKIT_ENV="test"
  # Deliberately NOT setting QUIET=1 here: bash-logger's --quiet means CONSOLE_LOG=false, which
  # suppresses ALL console output including error()/fatal() -- and plenty of tests assert on
  # exactly that text via `assert_output --partial`. Partial matching already tolerates the
  # extra "Starting FUNCNAME(...)" debug-trace noise those calls add, so there's no need to
  # suppress it.
}

# common_teardown()
#
# Call from every .bats file's teardown(). Removes the scratch directory common_setup created.
#
# Globals:
#   TEST_DIR   Set by common_setup.
common_teardown() {
  [[ -n "${TEST_DIR:-}" ]] && rm -rf "${TEST_DIR}"
}

# Loading bats-mock/stub above already prepends its stub bindir onto PATH for the whole test
# process — call its `stub`/`unstub`/`stub_repeated` functions directly, no wrapper needed here.

# Testing a hack/bin/*.sh entry point (test/bin/):
#
# Run it with `run hack/bin/<name>.sh ...` instead of sourcing it. It calls `main "$@"` as its
# last line, and running it keeps $0 right for its usage text. See test/bin/*.bats.
#
# Testing a hack/lib/**/*.sh file (test/lib/):
#
# hack/lib files load bashkit, whose libraries call `import`, so source bashkit's bootstrap
# before the file under test. Without it, `import` runs ImageMagick's import(1), which hangs
# waiting for a mouse click. Both can be sourced in setup(): functions and the files' `readonly`
# constants are global, so they are still defined in each @test body.
#
#   setup() {
#     common_setup
#     source hack/vendor/bashkit/local/lib/bashkit/os/bk-bootstrap.sh
#     source hack/lib/kubevirt/kubevirt.sh
#   }
#
#   @test "kubevirt::deploy fails when the kustomize dir is missing" {
#     run kubevirt::deploy "${TEST_DIR}/missing"
#     assert_failure
#     assert_output --partial "kustomize dir not found"
#   }
#
# The bootstrap turns on errexit, nounset and pipefail for the test. A sourced file that set a
# global with a plain `declare` at its top level would lose it here: bats runs setup() as a
# function, so the variable would be local to it. hack/lib and bashkit use `readonly` or
# `declare -g` for that reason (bashkit's docs/STYLEGUIDE.md §3.2).
