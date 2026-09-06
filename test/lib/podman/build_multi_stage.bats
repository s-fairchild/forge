#!/usr/bin/env bats
#
# Tests for hack/lib/podman/build/build_multi_stage.sh.
#
# See test/test_helper.bash's "IMPORTANT" comment: each @test sources the file under test as
# its own first line, never in setup().
#
# Mocking: `podman build` is mocked via bats-mock. `load_podman_build_env()`'s BUILD_ENV_BASE is
# a hardcoded `declare -r` computed from $PWD in hack/lib/podman/build/constants.env (not
# overridable), so it always resolves to the real hack/env/podman/build/ directory -- these
# tests use the real, already-checked-in example.env fixture there rather than fabricating one
# under TEST_DIR.

load "${PWD}/test/test_helper"

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "podman_build appends --format=docker and a --build-arg=BUILD_THREADS, then runs podman build" {
  source hack/lib/podman/build/build_multi_stage.sh
  local -a my_opts=(--pull)
  stub podman "build --pull --format=docker --build-arg=BUILD_THREADS=* ${TEST_DIR} : echo built"

  run podman_build my_opts "${TEST_DIR}"
  assert_success
  assert_output --partial "built"

  unstub podman
}

@test "podman_build forwards a non-zero podman exit status" {
  source hack/lib/podman/build/build_multi_stage.sh
  local -a my_opts=()
  stub podman "build * : exit 9"

  run podman_build my_opts "${TEST_DIR}"
  assert_failure 9

  unstub podman
}

@test "add_build_arg_file appends --build-arg-file when the file exists" {
  source hack/lib/podman/build/build_multi_stage.sh
  local -r context="${TEST_DIR}"
  touch "${context}/${ARGFILE_CONF}"
  local -a my_opts=()

  add_build_arg_file my_opts
  [[ "${my_opts[0]}" == "--build-arg-file=${context}/${ARGFILE_CONF}" ]]
}

@test "add_build_arg_file warns and no-ops when the file is missing" {
  source hack/lib/podman/build/build_multi_stage.sh
  local -r context="${TEST_DIR}"
  local -a my_opts=()

  run bash -c "
    source hack/lib/podman/build/build_multi_stage.sh
    context='${TEST_DIR}'
    my_opts=()
    add_build_arg_file my_opts
    echo \"count=\${#my_opts[@]}\"
  "
  assert_success
  assert_output --partial "Build arg file not found"
  assert_output --partial "count=0"
}

@test "load_podman_build_env populates build args, contexts, and the primary tag from a real .env fixture" {
  source hack/lib/podman/build/build_multi_stage.sh
  local -A args=()
  local -A contexts=()
  local tag=""

  load_podman_build_env "example" args contexts tag
  [[ -n "${tag}" ]]
  (( ${#args[@]} > 0 || ${#contexts[@]} > 0 ))
}

@test "load_podman_build_env fails via fatal when the per-image .env file does not exist" {
  run bash -c "source hack/lib/podman/build/build_multi_stage.sh; declare -A a c; t=''; load_podman_build_env no-such-image a c t"
  assert_failure 5
  assert_output --partial "file not found"
}

@test "add_build_primary_tag appends --tag=<repo>/<image>:<tag>" {
  source hack/lib/podman/build/build_multi_stage.sh
  local -a my_opts=()
  add_build_primary_tag my_opts "localhost/myrepo" "myimage" "v1.2.3"
  [[ "${my_opts[0]}" == "--tag=localhost/myrepo/myimage:v1.2.3" ]]
}

@test "add_build_args appends one --build-arg=<key>=<value> per entry" {
  source hack/lib/podman/build/build_multi_stage.sh
  local -A build_args=(["FOO"]="bar")
  local -a my_opts=()
  add_build_args my_opts build_args
  [[ "${my_opts[0]}" == "--build-arg=FOO=bar" ]]
}

@test "add_build_additional_contexts appends one --build-context=<key>=<value> per entry" {
  source hack/lib/podman/build/build_multi_stage.sh
  local -A build_contexts=(["base"]="docker://alpine")
  local -a my_opts=()
  add_build_additional_contexts my_opts build_contexts
  [[ "${my_opts[0]}" == "--build-context=base=docker://alpine" ]]
}

@test "add_container_files_ordered discovers and sorts Containerfile* by version" {
  source hack/lib/podman/build/build_multi_stage.sh
  touch "${TEST_DIR}/Containerfile.2"
  touch "${TEST_DIR}/Containerfile.10"
  touch "${TEST_DIR}/Containerfile.1"
  local -a my_opts=()

  add_container_files_ordered my_opts "${TEST_DIR}"
  (( ${#my_opts[@]} == 3 ))
  [[ "${my_opts[0]}" == "--file=${TEST_DIR}/Containerfile.1" ]]
  [[ "${my_opts[1]}" == "--file=${TEST_DIR}/Containerfile.2" ]]
  [[ "${my_opts[2]}" == "--file=${TEST_DIR}/Containerfile.10" ]]
}

@test "add_container_files_ordered skips discovery when -f/--file is already present" {
  source hack/lib/podman/build/build_multi_stage.sh
  touch "${TEST_DIR}/Containerfile"
  local -a my_opts=(--file=already-set)

  run bash -c "
    source hack/lib/podman/build/build_multi_stage.sh
    my_opts=(--file=already-set)
    add_container_files_ordered my_opts '${TEST_DIR}'
    echo \"count=\${#my_opts[@]}\"
  "
  assert_success
  assert_output --partial "Skipping addition"
  assert_output --partial "count=1"
}

@test "build_context_get reads element 0 as the context dir and drops the last element" {
  # NOTE: despite its doc comment ("Pops the last element ... as the build context"), the actual
  # implementation reads `opts[0]` as the context directory and separately `unset`s `opts[-1]` --
  # those are the same element only in the single-element case. Testing the real behavior, not
  # the documented one, per task instructions (not fixing this).
  source hack/lib/podman/build/build_multi_stage.sh
  local -a my_opts=("${TEST_DIR}")
  local my_ctx=""

  build_context_get my_opts my_ctx
  [[ "${my_ctx}" == "${TEST_DIR}" ]]
  (( ${#my_opts[@]} == 0 ))
}

@test "build_context_get fails via fatal when the context directory does not exist" {
  run bash -c "source hack/lib/podman/build/build_multi_stage.sh; my_opts=(/no/such/dir); my_ctx=''; build_context_get my_opts my_ctx"
  assert_failure
  assert_output --partial "Context directory not found"
}

@test "log_image_tags logs every tag" {
  source hack/lib/podman/build/build_multi_stage.sh
  local -a my_tags=("latest" "v1.2.3")
  run log_image_tags my_tags
  assert_success
  assert_output --partial "--tag=latest"
  assert_output --partial "--tag=v1.2.3"
}

@test "podman_build_with_options orchestrates a full build against the real example.env fixture" {
  source hack/lib/podman/build/build_multi_stage.sh
  mkdir -p "${TEST_DIR}/my_ctx"
  touch "${TEST_DIR}/my_ctx/Containerfile"
  # Wildcard the whole call: podman_build_with_options assembles many options (from the real
  # example.env fixture, discovered Containerfiles, etc.) whose exact order/count isn't this
  # test's concern -- exact single-option argument construction is covered by the dedicated
  # add_build_*/add_container_files_ordered tests above. This just proves the full orchestration
  # runs end-to-end successfully.
  stub podman "build * : echo built-with-options"

  local -a my_opts=()
  run podman_build_with_options my_opts "example" "${TEST_DIR}/my_ctx"
  assert_success
  assert_output --partial "built-with-options"

  unstub podman
}

@test "the double-inclusion guard variable is set after sourcing" {
  source hack/lib/podman/build/build_multi_stage.sh
  [[ "${__hack_lib_podman_build_multi_stage_sourced}" == true ]]
}
