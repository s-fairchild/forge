#!/usr/bin/env bats
#
# Tests for hack/lib/checksum/sha512sum.sh.

load "${PWD}/test/test_helper"

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "sha512sum delegates straight to the real coreutils binary" {
  source hack/lib/checksum/sha512sum.sh
  printf 'hello' > "${TEST_DIR}/input"
  expected="$(command sha512sum < "${TEST_DIR}/input")"

  run sha512sum < "${TEST_DIR}/input"
  assert_success
  assert_output "${expected}"
}

@test "sha512sum_gen_stdin hashes piped input" {
  source hack/lib/checksum/sha512sum.sh
  printf 'hello' > "${TEST_DIR}/input"
  expected="$(command sha512sum - < "${TEST_DIR}/input")"

  run sha512sum_gen_stdin < "${TEST_DIR}/input"
  assert_success
  assert_output "${expected}"
}

# sha512sum_gen_stdin/sha512sum_gen/sha512sum_check's "no input" failure path only triggers when
# `[[ -t 0 ]]` is true (a real controlling tty attached to stdin, with no piped/redirected
# input). bats never attaches a real tty to a test's stdin, and closing the fd (`<&-`) doesn't
# make `-t 0` true either (a closed fd isn't a terminal) -- it instead hangs bats' `run` waiting
# on a read against the closed descriptor in this environment. That failure path is therefore not
# reachable from an automated bats test without a real pty (e.g. via `script`/`expect`), so it's
# intentionally not covered here; the "input provided via argument" and "input provided via
# piped stdin" paths above and below this comment cover the rest of each function's behavior.

@test "sha512sum_gen hashes an argument without needing stdin" {
  source hack/lib/checksum/sha512sum.sh
  # sha512sum_gen feeds its input through `sha512sum_gen_stdin <<< "${input}"`, and `<<<` always
  # appends a trailing newline -- so the value actually hashed is "hello\n", not "hello".
  printf 'hello\n' > "${TEST_DIR}/input"
  expected="$(command sha512sum - < "${TEST_DIR}/input")"

  run sha512sum_gen "hello"
  assert_success
  assert_output "${expected}"
}

@test "sha512sum_gen hashes piped stdin when no argument is given" {
  source hack/lib/checksum/sha512sum.sh
  # Same `<<<`-adds-a-newline caveat as above applies here too, even though the piped input
  # itself has no trailing newline (command substitution strips it, then <<< re-adds exactly one).
  printf 'hello\n' > "${TEST_DIR}/input"
  expected="$(command sha512sum - < "${TEST_DIR}/input")"

  printf 'hello' > "${TEST_DIR}/piped"
  run sha512sum_gen < "${TEST_DIR}/piped"
  assert_success
  assert_output "${expected}"
}

@test "sha512sum_check_stdin verifies a matching checksum line" {
  echo -n "hello" > "${TEST_DIR}/data.txt"
  (cd "${TEST_DIR}" && command sha512sum data.txt > line.txt)

  run bash -c "source '${REPO_ROOT}/hack/lib/checksum/sha512sum.sh' && cd '${TEST_DIR}' && sha512sum_check_stdin < line.txt"
  assert_success
}

@test "sha512sum_check_stdin fails on a mismatched checksum line" {
  source hack/lib/checksum/sha512sum.sh
  echo -n "hello" > "${TEST_DIR}/data.txt"
  local -r bad_line="0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000  data.txt"
  printf '%s\n' "${bad_line}" > "${TEST_DIR}/line.txt"

  run bash -c "source '${REPO_ROOT}/hack/lib/checksum/sha512sum.sh' && cd '${TEST_DIR}' && sha512sum_check_stdin < line.txt"
  assert_failure
}

@test "sha512sum_check verifies a matching checksum line passed as an argument" {
  echo -n "hello" > "${TEST_DIR}/data.txt"
  local -r line="$(cd "${TEST_DIR}" && command sha512sum data.txt)"

  run bash -c "source '${REPO_ROOT}/hack/lib/checksum/sha512sum.sh' && cd '${TEST_DIR}' && sha512sum_check '${line}'"
  assert_success
}


# sha512sum_check's "no input" failure path has the same real-tty-only reachability caveat noted
# above for sha512sum_gen_stdin/sha512sum_gen -- not coverable here without a real pty.
