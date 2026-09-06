#!/usr/bin/env bats
#
# Tests for hack/lib/ignition/ignition.sh.
#
# Uses `run --separate-stderr`, which requires bats >= 1.5.0.
bats_require_minimum_version 1.5.0
#
# See test/test_helper.bash's "IMPORTANT" comment: each @test sources the file(s) under test as
# its own first line(s), never in setup() -- sourcing from setup() would make ignition.sh's
# `declare -r` constants local to setup() and gone by the time the @test body runs.
#
# Mocking strategy:
#   - yq() (hack/lib/yq.sh) and butane() (hack/lib/ignition/butane.sh) are thin podman wrappers,
#     so every call ignition.sh makes into a container is intercepted by stubbing the `podman`
#     binary itself with bats-mock (as test/lib/ignition/ignition-validate.bats already does for
#     ignition-validate.sh).
#   - jq (ignition_merge_read_inline_path/ignition_merge_write_entry) and sha512sum/the
#     hack/lib/checksum/*.sh helpers are real, un-mocked host tools -- their output is part of
#     what these tests verify (e.g. the verification hash is checked against an independently
#     computed `sha512sum` of the exact same bytes).
#   - Functions that return data via nameref out-parameters (ignition_merge_compile_entry,
#     ignition_gen_config_merge_inlines, get_secrets_from_env) are called *directly* in the
#     @test body, never via bats' `run` -- `run` forks a subshell, and a nameref mutation made
#     inside that subshell would vanish the instant `run` returns, before the assertion could
#     see it. This mirrors the exact reason ignition.sh's own doc comment gives for using
#     namerefs instead of stdout in the first place (see ignition_merge_compile_entry's header).
#
# A real, reproducible bug was found in get_secrets_from_env() and source_env_files() while
# writing these tests -- see the comments above the tests tagged "BUG" below for detail. Per
# task instructions this is documented here, not fixed.

load "${PWD}/test/test_helper"

setup() {
  common_setup
  # Deterministic podman_run_options: don't let a leaked PODMAN_LOG_LEVEL from the outer
  # environment insert an extra --log-level=... arg into butane()'s podman invocation.
  unset -v PODMAN_LOG_LEVEL
}

teardown() {
  common_teardown
}

# rel_fixture_path()
#
# ignition_gen() mounts "${PWD}/$(dirname "${butane_path}")" into the butane container and
# requires that resolved directory to actually exist (butane()'s -d check) -- so every
# butane_path used in these tests must be expressed *relative to the repo root* (PWD, per
# common_setup's cd), even though the real file lives under TEST_DIR (usually under /tmp,
# outside the repo). `realpath --relative-to` produces the right number of "../" segments so
# that "${PWD}/<that relative path>" resolves back to TEST_DIR.
rel_fixture_path() {
  realpath --relative-to="${PWD}" "$1"
}

# ============================================================================
# Double-inclusion guard
# ============================================================================

@test "the double-inclusion guard variable lets a caller skip re-sourcing" {
  source hack/lib/ignition/ignition.sh
  [[ "${__hack_lib_ignition_sourced}" == true ]]
}

# ============================================================================
# ignition_gen()
# ============================================================================

@test "ignition_gen requires a butane_path operand" {
  source hack/lib/ignition/ignition.sh
  run ignition_gen
  assert_failure
  assert_output --partial "operand is required"
}

@test "ignition_gen compiles a butane file via containerized butane and prints ignition JSON" {
  source hack/lib/ignition/ignition.sh

  local butane_path
  butane_path="$(rel_fixture_path "${TEST_DIR}")/sub.bu"
  touch "${TEST_DIR}/sub.bu"

  stub podman \
    "run --mount=* --security-opt=label=disable -i --rm --env='BU_*' --env='BUTANE_*' --workdir=/data quay.io/coreos/butane:release --strict --files-dir=files --raw sub.bu : echo '{\"ignition\":{\"version\":\"3.4.0\"}}'"

  run --separate-stderr ignition_gen "${butane_path}"
  assert_success
  assert_output '{"ignition":{"version":"3.4.0"}}'

  unstub podman
}

@test "ignition_gen passes each secret name through as a podman --secret mount option" {
  source hack/lib/ignition/ignition.sh

  local butane_path
  butane_path="$(rel_fixture_path "${TEST_DIR}")/sub.bu"
  touch "${TEST_DIR}/sub.bu"

  # shellcheck disable=SC2034
  declare -a secret_names=("mysecret")

  stub podman \
    "run --secret=mysecret,type=mount,target=/data/files/secrets/mysecret --mount=* --security-opt=label=disable -i --rm --env='BU_*' --env='BUTANE_*' --workdir=/data quay.io/coreos/butane:release --strict --files-dir=files --raw sub.bu : echo '{\"ignition\":{\"version\":\"3.4.0\"}}'"

  run --separate-stderr ignition_gen "${butane_path}" secret_names
  assert_success
  assert_output '{"ignition":{"version":"3.4.0"}}'

  unstub podman
}

@test "ignition_gen returns 1 and logs an error when butane compilation fails" {
  source hack/lib/ignition/ignition.sh

  local butane_path
  butane_path="$(rel_fixture_path "${TEST_DIR}")/sub.bu"
  touch "${TEST_DIR}/sub.bu"

  stub podman "run * : exit 3"

  run ignition_gen "${butane_path}"
  assert_failure
  assert_output --partial "ignition generation failed for ${butane_path}"

  unstub podman
}

# ============================================================================
# ignition_merge_read_inline_path()
# ============================================================================

# Shared jq bounds-check snippet, copied verbatim from ignition_gen_config_merge_inlines()'s
# _jq_bounds_check local -- ignition_merge_read_inline_path()/ignition_merge_write_entry() take
# it as a parameter rather than defining it themselves, so callers (including these tests) must
# supply the exact same definition.
# shellcheck disable=SC2016
JQ_BOUNDS_CHECK='def bounds_check(expr):
        if (getpath($merge_jq_path) | length) > $idx then expr
        else "Index \($idx) out of bounds" | halt_error(1) end;'
MERGE_JQ_PATH='["ignition", "config", "merge"]'

@test "ignition_merge_read_inline_path reads the inline path at the given index" {
  source hack/lib/ignition/ignition.sh

  local config_json='{"ignition":{"config":{"merge":[{"inline":"a.bu"},{"inline":"b.bu"}]}}}'

  run ignition_merge_read_inline_path "${config_json}" "${MERGE_JQ_PATH}" 0 "${JQ_BOUNDS_CHECK}"
  assert_success
  assert_output "a.bu"

  run ignition_merge_read_inline_path "${config_json}" "${MERGE_JQ_PATH}" 1 "${JQ_BOUNDS_CHECK}"
  assert_success
  assert_output "b.bu"
}

@test "ignition_merge_read_inline_path halts with an out-of-bounds index" {
  source hack/lib/ignition/ignition.sh

  local config_json='{"ignition":{"config":{"merge":[{"inline":"a.bu"}]}}}'

  run ignition_merge_read_inline_path "${config_json}" "${MERGE_JQ_PATH}" 1 "${JQ_BOUNDS_CHECK}"
  assert_failure
  assert_output --partial "Index 1 out of bounds"
}

# ============================================================================
# ignition_merge_write_entry()
# ============================================================================

@test "ignition_merge_write_entry writes the inline JSON and verification hash at the given index" {
  source hack/lib/ignition/ignition.sh

  local config_json='{"ignition":{"config":{"merge":[{"inline":"a.bu"}]}}}'
  local ignition_json='{"ignition":{"version":"3.4.0"}}'
  local verification_hash="sha512-deadbeef"

  run ignition_merge_write_entry "${config_json}" "${MERGE_JQ_PATH}" 0 "${JQ_BOUNDS_CHECK}" \
    "${ignition_json}" "${verification_hash}"
  assert_success

  # $output is compact JSON (jq -rc) -- decode it with a second, independent jq call rather
  # than string-matching, since key order/whitespace are jq's choice, not part of the contract.
  local got_inline got_hash
  got_inline="$(jq -r '.ignition.config.merge[0].inline' <<< "${output}")"
  got_hash="$(jq -r '.ignition.config.merge[0].verification.hash' <<< "${output}")"
  [ "${got_inline}" = "${ignition_json}" ]
  [ "${got_hash}" = "${verification_hash}" ]
}

@test "ignition_merge_write_entry halts with an out-of-bounds index" {
  source hack/lib/ignition/ignition.sh

  local config_json='{"ignition":{"config":{"merge":[{"inline":"a.bu"}]}}}'

  run ignition_merge_write_entry "${config_json}" "${MERGE_JQ_PATH}" 5 "${JQ_BOUNDS_CHECK}" \
    '{"ignition":{}}' "sha512-deadbeef"
  assert_failure
  assert_output --partial "Index 5 out of bounds"
}

# ============================================================================
# ignition_merge_compile_entry()
# ============================================================================
#
# Uses nameref out-params -- called directly (no `run`), see the file header comment.

@test "ignition_merge_compile_entry compiles and hashes a butane file, returned via nameref" {
  source hack/lib/ignition/ignition.sh

  local butane_path
  butane_path="$(rel_fixture_path "${TEST_DIR}")/sub.bu"
  touch "${TEST_DIR}/sub.bu"

  stub podman "run * : echo '{\"ignition\":{\"version\":\"3.4.0\"}}'"

  # Deliberately NOT named ignition_json_out/verification_hash_out: those are the callee's own
  # `local -n` nameref parameter names, and binding a caller-side variable of the identical name
  # to a nameref argument creates a self-referential nameref ("circular name reference").
  local my_json my_hash
  ignition_merge_compile_entry "${butane_path}" my_json my_hash
  local status=$?

  [ "${status}" -eq 0 ]
  [ "${my_json}" = '{"ignition":{"version":"3.4.0"}}' ]

  # Independently recompute the expected hash with the real, un-mocked sha512sum -- this is the
  # exact algorithm ignition.sh's own doc comment calls out: printf '%s' (no trailing newline).
  local expected_hash
  expected_hash="sha512-$(printf '%s' "${my_json}" | sha512sum | cut -d' ' -f1)"
  [ "${my_hash}" = "${expected_hash}" ]

  unstub podman
}

@test "ignition_merge_compile_entry returns 1 when the underlying butane compile fails" {
  source hack/lib/ignition/ignition.sh

  local butane_path
  butane_path="$(rel_fixture_path "${TEST_DIR}")/sub.bu"
  touch "${TEST_DIR}/sub.bu"

  stub podman "run * : exit 3"

  run bash -c "
    source hack/lib/ignition/ignition.sh
    ignition_merge_compile_entry '${butane_path}' ignition_json_out verification_hash_out
  "
  assert_failure
  assert_output --partial "failed to generate ignition config from: ${butane_path}"

  unstub podman
}

# ============================================================================
# ignition_gen_config_merge_inlines()
# ============================================================================
#
# Full end-to-end coverage (real multi-entry config, exact podman argument verification on
# every call) proved impractical to fixture: each merge entry drives two containerized calls
# (yq to reparse, butane to recompile) whose exact argv depends on dynamic TEST_DIR paths, and
# bats-mock's stub matches patterns positionally by naive whitespace-splitting -- so exact
# argument assertions are kept to ignition_gen()'s own tests above (a single call, in isolation)
# rather than repeated here. What IS covered end-to-end below: a real 1-entry merge, verifying
# the final output and (by capturing the final butane call's stdin) that the intermediate
# config_json produced by the merge loop is byte-correct -- exact inline JSON and a matching
# sha512- verification hash -- plus every documented failure branch (missing top-level file, yq
# parse failure, per-entry compile failure, final compile failure). Multi-entry (2+) looping is
# not separately covered; the loop body is identical per iteration and is otherwise fully
# exercised by the 1-entry case, plus ignition_merge_read/write_entry's own index-based tests
# above already cover indexing across multiple entries.

@test "ignition_gen_config_merge_inlines returns 1 when the top-level butane file does not exist" {
  source hack/lib/ignition/ignition.sh

  local missing_path="${TEST_DIR}/does-not-exist.bu"
  local merge_out
  # `cmd || status=$?`, not `cmd; status=$?` -- bats runs test bodies with errexit active, so a
  # direct (non-`run`) call that returns non-zero would abort the test right there, before the
  # next statement (the status capture) ever executed. Being the last element of an `||` list
  # exempts this specific call from that.
  local status=0
  ignition_gen_config_merge_inlines "${missing_path}" merge_out || status=$?

  [ "${status}" -eq 1 ]
}

@test "ignition_gen_config_merge_inlines merges one entry end-to-end with a correct inline and verification hash" {
  source hack/lib/ignition/ignition.sh

  local sub_rel main_bu
  sub_rel="$(rel_fixture_path "${TEST_DIR}")/sub.bu"
  main_bu="${TEST_DIR}/main.bu"
  touch "${TEST_DIR}/sub.bu"
  cat > "${main_bu}" <<BU
variant: fcos
version: 1.5.0
BU

  local sub_ignition_json='{"ignition":{"version":"3.4.0"},"storage":{"files":[]}}'
  local final_ignition_json='{"ignition":{"version":"3.4.0","config":{"merge":[]}}}'

  # Three sequential, unconditional podman calls in this exact order: (1) yq parsing main.bu to
  # JSON, (2) butane compiling the merge entry's sub.bu, (3) the final merged-config butane
  # compile. bats-mock matches plan lines by call *index*, not by argument content, when no
  # pattern is given before " : " -- so each line here always "matches" whichever call it is,
  # regardless of the real (dynamic, TEST_DIR-dependent) argv passed to podman for that call.
  stub podman \
    "echo '{\"ignition\":{\"config\":{\"merge\":[{\"inline\":\"${sub_rel}\"}]}}}'" \
    "echo '${sub_ignition_json}'" \
    "cat > '${TEST_DIR}/final_stdin.json'; echo '${final_ignition_json}'"

  local merge_out
  ignition_gen_config_merge_inlines "${main_bu}" merge_out
  local status=$?

  [ "${status}" -eq 0 ]
  [ "${merge_out}" = "${final_ignition_json}" ]

  # Verify the intermediate config_json (captured via the final butane call's stdin) got the
  # correct inline JSON and a verification hash matching a real, independently computed sha512.
  local captured
  captured="$(cat "${TEST_DIR}/final_stdin.json")"
  local expected_hash
  expected_hash="sha512-$(printf '%s' "${sub_ignition_json}" | sha512sum | cut -d' ' -f1)"

  local got_inline got_hash
  got_inline="$(jq -r '.ignition.config.merge[0].inline' <<< "${captured}")"
  got_hash="$(jq -r '.ignition.config.merge[0].verification.hash' <<< "${captured}")"
  [ "${got_inline}" = "${sub_ignition_json}" ]
  [ "${got_hash}" = "${expected_hash}" ]

  unstub podman
}

@test "ignition_gen_config_merge_inlines returns 1 when the yq parse step fails" {
  source hack/lib/ignition/ignition.sh

  local main_bu="${TEST_DIR}/main.bu"
  cat > "${main_bu}" <<BU
variant: fcos
version: 1.5.0
BU

  stub podman "run * : exit 4"

  run bash -c "
    source hack/lib/ignition/ignition.sh
    merge_out=''
    ignition_gen_config_merge_inlines '${main_bu}' merge_out
  "
  assert_failure
  assert_output --partial "failed to load config json from: ${main_bu}"

  unstub podman
}

@test "ignition_gen_config_merge_inlines returns 1 when a merge entry fails to compile" {
  source hack/lib/ignition/ignition.sh

  local sub_rel main_bu
  sub_rel="$(rel_fixture_path "${TEST_DIR}")/sub.bu"
  main_bu="${TEST_DIR}/main.bu"
  touch "${TEST_DIR}/sub.bu"
  cat > "${main_bu}" <<BU
variant: fcos
version: 1.5.0
BU

  stub podman \
    "echo '{\"ignition\":{\"config\":{\"merge\":[{\"inline\":\"${sub_rel}\"}]}}}'" \
    "exit 7"

  run bash -c "
    source hack/lib/ignition/ignition.sh
    merge_out=''
    ignition_gen_config_merge_inlines '${main_bu}' merge_out
  "
  assert_failure
  assert_output --partial "failed to compile ignition merge inline entry"

  unstub podman
}

@test "ignition_gen_config_merge_inlines returns 1 when the final merged-config compile fails" {
  source hack/lib/ignition/ignition.sh

  local sub_rel main_bu
  sub_rel="$(rel_fixture_path "${TEST_DIR}")/sub.bu"
  main_bu="${TEST_DIR}/main.bu"
  touch "${TEST_DIR}/sub.bu"
  cat > "${main_bu}" <<BU
variant: fcos
version: 1.5.0
BU

  stub podman \
    "echo '{\"ignition\":{\"config\":{\"merge\":[{\"inline\":\"${sub_rel}\"}]}}}'" \
    "echo '{\"ignition\":{\"version\":\"3.4.0\"}}'" \
    "exit 9"

  run bash -c "
    source hack/lib/ignition/ignition.sh
    merge_out=''
    ignition_gen_config_merge_inlines '${main_bu}' merge_out
  "
  assert_failure
  assert_output --partial "failed to compile merged butane config to ignition JSON"

  unstub podman
}

# ============================================================================
# get_secrets_from_env()
# ============================================================================
#
# BUG: get_secrets_from_env()'s array-type validation is inverted. It checks
#   [[ ${!names@a} == *a* ]] -> error "must be an indexed array"; return 1
# but `${!names@a}` (nameref attribute introspection) reports the lowercase "a" flag *only when
# names already IS a properly declared indexed array* (declare -A gives "A", unset/scalar gives
# ""). So the one call shape the function's own usage doc recommends -- pre-declaring the output
# array before passing it, e.g. `declare -a out=(); get_secrets_from_env out` -- is exactly the
# shape that trips this check and makes the function fail immediately, before ever looking at
# SECRET_FILES/SECRET_IDS. The only way to reach the real logic is to pass a nameref target that
# is *not yet* a declared indexed array (unset, or an associative array) and let `names+=(...)`
# autovivify it later. source_env_files() has the identical bug (see below). Neither function
# has any caller anywhere in this repo today (grep confirms), so this is currently dormant, but
# it means both are unusable via their documented call convention. Not fixed here per task
# instructions -- tests below document the bug directly and use the unset-nameref workaround to
# still exercise the rest of each function's logic.

@test "BUG: get_secrets_from_env rejects a properly pre-declared indexed array (inverted check)" {
  source hack/lib/ignition/ignition.sh

  # shellcheck disable=SC2034
  declare -a secret_names_out=()
  # `cmd || status=$?`, not `cmd; status=$?` -- see the identical comment on
  # ignition_gen_config_merge_inlines's "file does not exist" test above: bats runs test bodies
  # with errexit active, so this direct (non-`run`) call returning 1 would otherwise abort the
  # test before the status capture ran.
  local status=0
  get_secrets_from_env secret_names_out "prod" || status=$?

  [ "${status}" -eq 1 ]
}

@test "get_secrets_from_env warns and succeeds with neither SECRET_FILES nor SECRET_IDS set" {
  run bash -c "
    source hack/lib/ignition/ignition.sh
    unset -v SECRET_FILES SECRET_IDS
    names_out=''
    get_secrets_from_env names_out 'prod'
  "
  assert_success
  assert_output --partial "SECRET_FILES"
}

@test "get_secrets_from_env creates a podman secret for each SECRET_FILES entry" {
  source hack/lib/ignition/ignition.sh
  source hack/lib/podman/podman-secret.sh

  touch "${TEST_DIR}/keyfile1" "${TEST_DIR}/keyfile2"
  # shellcheck disable=SC2034
  declare -a SECRET_FILES=("${TEST_DIR}/keyfile1" "${TEST_DIR}/keyfile2")

  stub podman \
    "secret exists keyfile1 : exit 1" \
    "secret create * : exit 0" \
    "secret exists keyfile2 : exit 1" \
    "secret create * : exit 0"

  # names_out deliberately left undeclared (no `declare -a`) -- see the BUG note above: this is
  # the only shape that doesn't immediately trip the inverted array-type check.
  unset -v names_out
  get_secrets_from_env names_out "prod"
  local status=$?

  [ "${status}" -eq 0 ]
  [ "${names_out[0]}" = "keyfile1" ]
  [ "${names_out[1]}" = "keyfile2" ]

  unstub podman
}

@test "get_secrets_from_env resolves existing SECRET_IDS and skips missing ones" {
  source hack/lib/ignition/ignition.sh

  # shellcheck disable=SC2034
  declare -a SECRET_IDS=("existing-id" "missing-id")

  stub podman \
    "secret exists existing-id : exit 0" \
    "secret inspect * : echo resolved-secret-name" \
    "secret exists missing-id : exit 1"

  unset -v names_out
  get_secrets_from_env names_out "prod"
  local status=$?

  [ "${status}" -eq 0 ]
  [ "${#names_out[@]}" -eq 1 ]
  [ "${names_out[0]}" = "resolved-secret-name" ]

  unstub podman
}

# ============================================================================
# source_env_files()
# ============================================================================
#
# See the BUG note above get_secrets_from_env()'s tests -- source_env_files() has the identical
# inverted array-type check, on its one and only "files" argument this time. A genuinely
# pre-declared indexed array of file paths (the only sensible way to call this function) always
# trips it. The workaround used below to still exercise the sourcing/missing-file logic is to
# pass an *associative* array instead (attribute "A", which the buggy `*a*` glob does not match)
# -- `"${files[@]}"` iterates an associative array's values just as well as an indexed array's.

@test "BUG: source_env_files rejects a properly pre-declared indexed array (inverted check)" {
  source hack/lib/ignition/ignition.sh

  echo 'FOO=bar' > "${TEST_DIR}/a.env"
  # shellcheck disable=SC2034
  declare -a env_files=("${TEST_DIR}/a.env")

  # `cmd || status=$?`, not `cmd; status=$?` -- see the identical comment on
  # ignition_gen_config_merge_inlines's "file does not exist" test above.
  local status=0
  source_env_files env_files || status=$?

  [ "${status}" -eq 1 ]
}

@test "source_env_files no-ops successfully with an empty/unset files array" {
  source hack/lib/ignition/ignition.sh

  unset -v env_files
  source_env_files env_files
  local status=$?

  [ "${status}" -eq 0 ]
}

@test "source_env_files sources every listed file into the current shell" {
  source hack/lib/ignition/ignition.sh

  echo 'FORGE_TEST_FOO=bar' > "${TEST_DIR}/a.env"
  echo 'FORGE_TEST_BAZ=qux' > "${TEST_DIR}/b.env"
  # shellcheck disable=SC2034
  declare -A env_files=([0]="${TEST_DIR}/a.env" [1]="${TEST_DIR}/b.env")

  unset -v FORGE_TEST_FOO FORGE_TEST_BAZ
  source_env_files env_files
  local status=$?

  [ "${status}" -eq 0 ]
  [ "${FORGE_TEST_FOO}" = "bar" ]
  [ "${FORGE_TEST_BAZ}" = "qux" ]
}

@test "source_env_files returns 1 and logs an error when a listed file does not exist" {
  source hack/lib/ignition/ignition.sh

  local missing="${TEST_DIR}/does-not-exist.env"

  run bash -c "
    source hack/lib/ignition/ignition.sh
    declare -A env_files=([0]='${missing}')
    source_env_files env_files
  "
  assert_failure
  assert_output --partial "file not found: ${missing}"
}
