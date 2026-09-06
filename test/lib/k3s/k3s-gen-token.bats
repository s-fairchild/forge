#!/usr/bin/env bats
#
# Tests for hack/lib/k3s/k3s-gen-token.sh.
#
# Uses `run --separate-stderr`, which requires bats >= 1.5.0.
bats_require_minimum_version 1.5.0
#
# See test/test_helper.bash's "IMPORTANT" comment: each @test sources the file under test as
# its own first line, never in setup().
#
# No mocking: every generator here is real, deterministic, offline local computation
# (openssl/tr/sha256sum/cut, all real host coreutils), so tests run them for real rather than
# stubbing anything, and just assert on the shape of the output (64 lowercase hex chars).

load "${PWD}/test/test_helper"

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# assert_64_lowercase_hex()
#
# Asserts $output (from a prior `run`) is exactly 64 lowercase hex characters.
assert_64_lowercase_hex() {
  [[ "${output}" =~ ^[0-9a-f]{64}$ ]] || {
    echo "expected 64 lowercase hex chars, got: [${output}] (${#output} chars)" >&2
    return 1
  }
}

# path_without()
#
# Builds a scratch bin/ directory under TEST_DIR that mirrors every real binary already on
# PATH (via symlinks) EXCEPT the tool names given -- so a test can set PATH to just that
# directory to simulate specific tools being "missing" (as far as `which`/PATH lookup is
# concerned) without losing access to every other real tool the sourcing chain needs
# (bash-logger, coreutils, etc.).
path_without() {
  local -a excluded=("$@")
  local -r bindir="${TEST_DIR}/path-without-${excluded[*]// /_}"
  mkdir -p "${bindir}"

  # Mirror every real binary already on PATH via symlinks in one `find | xargs` pass rather than
  # a bash `for` loop over (often thousands of) files -- bats installs a DEBUG trap that fires on
  # every bash command, and a per-file bash loop over a directory the size of /usr/bin gets very
  # slow under that trap (fine standalone, but slow enough under bats to blow past a test
  # timeout). Farming the per-file work out to find/xargs keeps it to a handful of bash commands.
  local -a name_excludes=()
  local excl
  for excl in "${excluded[@]}"; do
    name_excludes+=(-not -name "${excl}")
  done

  local dir
  local -a dirs
  IFS=':' read -ra dirs <<< "${PATH}"
  for dir in "${dirs[@]}"; do
    [[ -d "${dir}" ]] || continue
    find "${dir}" -maxdepth 1 -type f -perm -u+x "${name_excludes[@]}" -print0 2> /dev/null \
      | xargs -0 -I{} ln -sf {} "${bindir}/" 2> /dev/null
  done
  printf '%s' "${bindir}"
}

@test "k3s_gen_token_openssl produces 64 lowercase hex characters" {
  source hack/lib/k3s/k3s-gen-token.sh
  run k3s_gen_token_openssl
  assert_success
  assert_64_lowercase_hex
}

@test "k3s_gen_token_tr produces 64 lowercase hex characters" {
  source hack/lib/k3s/k3s-gen-token.sh
  run k3s_gen_token_tr
  assert_success
  assert_64_lowercase_hex
}

@test "k3s_gen_token_shasum produces 64 lowercase hex characters" {
  source hack/lib/k3s/k3s-gen-token.sh
  run k3s_gen_token_shasum
  assert_success
  assert_64_lowercase_hex
}

@test "k3s_gen_token uses openssl when available" {
  source hack/lib/k3s/k3s-gen-token.sh
  run k3s_gen_token
  assert_success
  assert_64_lowercase_hex
  refute_output --partial "Falling back"
}

@test "k3s_gen_token falls back to tr when openssl is unavailable" {
  local -r bindir="$(path_without openssl)"
  run --separate-stderr env PATH="${bindir}" bash -c '
    source hack/lib/k3s/k3s-gen-token.sh
    k3s_gen_token
  '
  assert_success
  [[ "${output}" =~ ^[0-9a-f]{64}$ ]]
  assert_stderr --partial "Falling back to tr"
}

@test "k3s_gen_token falls back to shasum when neither openssl nor tr is available" {
  local -r bindir="$(path_without openssl tr)"
  run --separate-stderr env PATH="${bindir}" bash -c '
    source hack/lib/k3s/k3s-gen-token.sh
    k3s_gen_token
  '
  assert_success
  [[ "${output}" =~ ^[0-9a-f]{64}$ ]]
  assert_stderr --partial "Falling back to shasum"
}

@test "the double-inclusion guard variable is set after sourcing" {
  source hack/lib/k3s/k3s-gen-token.sh
  [[ "${__hack_lib_k3s_gen_token_sourced}" == true ]]
}
