#!/usr/bin/env bats
#
# Tests for hack/vendor/bash-logger-adapter/adapter.sh.
#
# See test/test_helper.bash's "IMPORTANT" comment: each @test sources the file under test as
# its own first line, never in setup() -- this matters enormously here, since adapter.sh
# declares ~15 ERROR_*/LOG_LEVEL_* readonly constants that fatal/error/warn/info/debug/log all
# depend on; sourcing from setup() would make every one of them vanish before the @test body
# runs, producing broken/empty log messages instead of a clean failure.

load "${PWD}/test/test_helper"

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "error/warn/info/debug each emit the message at their named severity" {
  # VERBOSE must be set *before* sourcing: adapter.sh captures it into a readonly at source time
  # and applies it via an unconditional bash_logger_adapter_apply_overrides call at the bottom of
  # the file, so setting it after sourcing is too late for debug-level output to appear.
  export VERBOSE=1
  source hack/vendor/bash-logger-adapter/adapter.sh

  run error "boom"
  assert_success
  assert_output --partial "ERROR"
  assert_output --partial "boom"

  run warn "careful"
  assert_success
  assert_output --partial "WARN"
  assert_output --partial "careful"

  run info "fyi"
  assert_success
  assert_output --partial "INFO"
  assert_output --partial "fyi"

  run debug "trace me"
  assert_success
  assert_output --partial "trace me"
}

@test "log() dispatches on an explicit recognized level keyword" {
  source hack/vendor/bash-logger-adapter/adapter.sh
  run log "${LOG_LEVEL_ERROR}" "explicit level"
  assert_success
  assert_output --partial "ERROR"
  assert_output --partial "explicit level"
}

@test "log() falls back to INFO for a bare message with no recognized level" {
  source hack/vendor/bash-logger-adapter/adapter.sh
  run log "just a message, no level"
  assert_success
  assert_output --partial "INFO"
  assert_output --partial "just a message, no level"
}

@test "sensitive() logs to the console" {
  source hack/vendor/bash-logger-adapter/adapter.sh
  run sensitive "topsecret"
  assert_success
  assert_output --partial "topsecret"
}

@test "fatal defaults to exit status 1" {
  run bash -c "source hack/vendor/bash-logger-adapter/adapter.sh; fatal 'going down'"
  assert_failure 1
  assert_output --partial "going down"
}

@test "fatal honors --status=N" {
  run bash -c "source hack/vendor/bash-logger-adapter/adapter.sh; fatal --status=42 'custom status'"
  assert_failure 42
}

@test "fatal honors --status N (separate argument form)" {
  run bash -c "source hack/vendor/bash-logger-adapter/adapter.sh; fatal --status 7 'custom status'"
  assert_failure 7
}

@test "bash_logger_adapter_apply_overrides requires all 3 arguments" {
  source hack/vendor/bash-logger-adapter/adapter.sh
  run bash_logger_adapter_apply_overrides 0 0
  assert_failure

  run bash_logger_adapter_apply_overrides 0 0 "${LOG_LEVEL_INFO}"
  assert_success
}

@test "cli_verbose=1 raises the level enough for debug output to appear" {
  source hack/vendor/bash-logger-adapter/adapter.sh
  bash_logger_adapter_apply_overrides 0 0 "${LOG_LEVEL_INFO}"
  run debug "hidden at info level"
  assert_success
  refute_output --partial "hidden at info level"

  bash_logger_adapter_apply_overrides 1 0 "${LOG_LEVEL_INFO}"
  run debug "shown once verbose"
  assert_success
  assert_output --partial "shown once verbose"
}

@test "the double-inclusion guard variable is set after sourcing" {
  source hack/vendor/bash-logger-adapter/adapter.sh
  [[ "${__bash_logger_adapter_sourced}" == true ]]
}
