# test/test_helper.bash
#
# Shared bats setup for the hack/ test suite. Every .bats file loads this via
# `load "${PWD}/test/test_helper"` — that only resolves correctly when bats is invoked from the
# repo root (as `make test`/`make coverage` do), matching this repo's existing "run from repo
# root" convention for hack/lib and hack/bin (see CLAUDE.md "Logging and Vendored Dependencies").

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
# Call from every .bats file's setup(). Ensures cwd is the repo root (hack/lib/*.sh and
# hack/bin/*.sh hardcode sourcing paths relative to it) and creates a fresh scratch directory
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

# IMPORTANT — sourcing hack/lib/*.sh (or hack/vendor/bash-logger-adapter/adapter.sh) in tests:
#
# Every one of those files declares its constants with `declare -r NAME=value` at what looks
# like file top-level — correct Google-style code when the file is sourced at a script's real
# top level (which is how hack/bin/*.sh and hack/lib/*.sh actually use each other). But bats
# runs `setup()`, each `@test` body, and `teardown()` as separate bash *functions*, and `declare`
# (with or without `-r`/`-a`/etc.) used inside any active function frame always creates a
# variable local to that frame -- never a global -- regardless of whether the name already
# exists. (Plain assignment without `declare`/`local`, and `export`, do NOT have this problem --
# only `declare`/`local`/`readonly` do.)
#
# Concretely: if you `source hack/lib/ignition/ignition.sh` inside `setup()`, every `declare -r`
# constant in that file (and transitively in adapter.sh/bashkit) becomes local to `setup()` and
# is destroyed the instant `setup()` returns -- by the time your `@test` body runs, those
# constants are gone (functions themselves are unaffected and stay callable, since function
# *definitions* are always global regardless of where they're defined; only the constants
# vanish). The same is true of sourcing at what looks like the .bats file's top level -- bats
# executes that in its own frame too, which also returns before your `@test` body runs.
#
# The only frame that's still active when your test logic runs is the `@test` body itself
# (bash's `local` variables are visible dynamically to whatever a still-active frame calls,
# including via bats' `run`). So: **always `source` the file under test as the first line
# inside the `@test { ... }` body, never in `setup()`** --
#
#   @test "ignition_validate -h prints usage" {
#     source hack/lib/ignition/ignition-validate.sh
#     run ignition_validate -h
#     assert_success
#   }
#
# `common_setup`/`common_teardown` (cwd + TEST_DIR) are unaffected by this and stay in
# setup()/teardown() as normal -- they only use plain assignment/export, not declare/local.
