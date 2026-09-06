#!/usr/bin/env bats
#
# Tests for hack/lib/podman/podman-secret.sh.
#
# See test/test_helper.bash's "IMPORTANT" comment: each @test sources the file under test as
# its own first line, never in setup().

load "${PWD}/test/test_helper"

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "podman_secret_exists reflects podman secret exists' exit status (success)" {
  source hack/lib/podman/podman-secret.sh
  stub podman "secret exists my-secret : exit 0"

  run podman_secret_exists my-secret
  assert_success

  unstub podman
}

@test "podman_secret_exists reflects podman secret exists' exit status (failure)" {
  source hack/lib/podman/podman-secret.sh
  stub podman "secret exists my-secret : exit 1"

  run podman_secret_exists my-secret
  assert_failure

  unstub podman
}

@test "usage_podman_secret_create_replace_from_stdin prints usage to stderr" {
  source hack/lib/podman/podman-secret.sh
  run usage_podman_secret_create_replace_from_stdin
  assert_success
  assert_output --partial "Usage: podman_secret_create_replace_from_stdin"
}

@test "podman_secret_create_replace_from_stdin -h prints usage without touching podman" {
  source hack/lib/podman/podman-secret.sh
  run podman_secret_create_replace_from_stdin -h
  assert_success
  assert_output --partial "Usage: podman_secret_create_replace_from_stdin"
}

@test "podman_secret_create_replace_from_stdin exits fatally on an unknown option" {
  run bash -c "source hack/lib/podman/podman-secret.sh; podman_secret_create_replace_from_stdin -z"
  assert_failure
  assert_output --partial "is unknown"
}

@test "podman_secret_create_replace_from_stdin exits fatally when secret_name is missing" {
  run bash -c "source hack/lib/podman/podman-secret.sh; echo -n data | podman_secret_create_replace_from_stdin"
  assert_failure
}

@test "podman_secret_create_replace_from_stdin exits fatally on empty stdin" {
  run bash -c "source hack/lib/podman/podman-secret.sh; podman_secret_create_replace_from_stdin my-secret < /dev/null"
  assert_failure
  assert_output --partial "input"
}

@test "podman_secret_create_replace_from_stdin creates the secret from stdin with provenance labels" {
  # 3 provenance labels are always appended (generated-by-file/-sourced-file/-function) --
  # bats-mock matches patterns positionally 1:1 against argv, so each needs its own wildcard.
  stub podman "secret create --replace --label=generated-by-file=* --label=generated-by-sourced-file=* --label=generated-by-function=* my-secret - : cat > /dev/null; echo secret-created"

  run bash -c "source hack/lib/podman/podman-secret.sh; echo -n 'my-data' | podman_secret_create_replace_from_stdin my-secret"
  assert_success
  assert_output --partial "secret-created"

  unstub podman
}

@test "podman_secret_create_replace_from_stdin fails via fatal when podman secret create fails" {
  stub podman "secret create --replace * : exit 1"

  run bash -c "source hack/lib/podman/podman-secret.sh; echo -n 'my-data' | podman_secret_create_replace_from_stdin my-secret"
  assert_failure
  assert_output --partial "failed to create podman secret"

  unstub podman
}

@test "podman_secret_showsecret exits fatally when the secret name is missing" {
  run bash -c "source hack/lib/podman/podman-secret.sh; podman_secret_showsecret"
  assert_failure
}

@test "podman_secret_showsecret prints the secret's raw data" {
  source hack/lib/podman/podman-secret.sh
  stub podman "secret inspect --showsecret -f {{.SecretData}} my-secret : echo raw-secret-data"

  run podman_secret_showsecret my-secret
  assert_success
  assert_output --partial "raw-secret-data"

  unstub podman
}

@test "usage_podman_secret_create_from_file prints usage to stderr" {
  source hack/lib/podman/podman-secret.sh
  run usage_podman_secret_create_from_file
  assert_success
  assert_output --partial "Usage: podman_secret_create_from_file"
}

@test "podman_secret_create_from_file rejects an unknown option" {
  source hack/lib/podman/podman-secret.sh
  run podman_secret_create_from_file -z
  assert_failure
  assert_output --partial "is unknown"
}

@test "podman_secret_create_from_file requires the src_files_nameref operand" {
  source hack/lib/podman/podman-secret.sh
  run podman_secret_create_from_file
  assert_failure
}

@test "podman_secret_create_from_file skips a secret that already exists" {
  source hack/lib/podman/podman-secret.sh
  stub podman "secret exists myfile.txt : exit 0"
  printf 'x' > "${TEST_DIR}/myfile.txt"
  # Deliberately not named src_files: that's the callee's own `local -n` nameref parameter name,
  # and reusing it here would create a self-referential nameref ("circular name reference").
  local -a my_src_files=("${TEST_DIR}/myfile.txt")

  run podman_secret_create_from_file my_src_files
  assert_success
  assert_output --partial "already exists"

  unstub podman
}

@test "podman_secret_create_from_file creates a secret per file" {
  source hack/lib/podman/podman-secret.sh
  printf 'x' > "${TEST_DIR}/myfile.txt"
  # 4 provenance labels are always appended (generated-by-file/-sourced-file/-function/filepath)
  # -- bats-mock matches patterns positionally 1:1 against argv, so each needs its own wildcard.
  stub podman \
    "secret exists myfile.txt : exit 1" \
    "secret create --ignore --label=generated-by-file=* --label=generated-by-sourced-file=* --label=generated-by-function=* --label=filepath=* myfile.txt ${TEST_DIR}/myfile.txt : echo file-secret-created"
  local -a my_src_files=("${TEST_DIR}/myfile.txt")

  run podman_secret_create_from_file my_src_files
  assert_success
  assert_output --partial "file-secret-created"

  unstub podman
}

# podman_secret_gen_file_secretsdata()'s TTY-detection failure path ([[ -t 0 ]], checked only
# *after* an unconditional `local -r input="$(cat)"`) has the same real-tty-only reachability
# caveat as sha512sum_gen_stdin/sha512sum_gen (see test/lib/checksum/sha512sum.bats) -- and this
# sandbox has no /dev/tty at all ("No such device or address"), so it's not coverable here.

@test "podman_secret_gen_file_secretsdata produces the expected JSON mapping" {
  # BUG (pre-existing, not fixed per task instructions): `mapfile secrets <<< "${input}"` is
  # missing `-t`, so each element keeps its trailing newline (e.g. $'secret-a\n') -- this is
  # passed straight through to `podman secret inspect --showsecret`, which in real usage would
  # never match a real secret name. Wildcard-matching the trailing newline here so the rest of
  # the function's JSON-construction logic still gets exercised.
  stub podman "secret inspect --showsecret secret-a* secret-b* : echo '[{\"ID\":\"id-a\",\"SecretData\":\"data-a\"},{\"ID\":\"id-b\",\"SecretData\":\"data-b\"}]'"

  run bash -c "source hack/lib/podman/podman-secret.sh; printf 'secret-a\nsecret-b\n' | podman_secret_gen_file_secretsdata"
  assert_success
  # jq's default output is pretty-printed (a space after each ":"), not compact -- the function
  # doesn't pass -c.
  assert_output --partial '"id-a": "data-a"'
  assert_output --partial '"id-b": "data-b"'

  unstub podman
}

@test "podman_secret_filter_by_label requires both label and value operands" {
  source hack/lib/podman/podman-secret.sh
  run podman_secret_filter_by_label only-one-arg
  assert_failure
}

@test "podman_secret_filter_by_label prints matching secret names" {
  stub podman \
    "secret ls -q : echo id-a" \
    "secret inspect id-a : echo '[{\"Spec\":{\"Name\":\"my-secret\",\"Labels\":{\"env\":\"prod\"}}}]'"

  run bash -c "source hack/lib/podman/podman-secret.sh; podman_secret_filter_by_label env prod"
  assert_success
  assert_output --partial "my-secret"

  unstub podman
}

@test "podman_secret_filter_by_label fails when no secret matches the filter" {
  stub podman \
    "secret ls -q : echo id-a" \
    "secret inspect id-a : echo '[{\"Spec\":{\"Name\":\"my-secret\",\"Labels\":{\"env\":\"staging\"}}}]'"

  run bash -c "source hack/lib/podman/podman-secret.sh; podman_secret_filter_by_label env prod"
  assert_failure
  assert_output --partial "no podman secret found"

  unstub podman
}

@test "sourcing podman-secret.sh sets its double-inclusion guard" {
  source hack/lib/podman/podman-secret.sh
  [[ "${__hack_lib_podman_secret_sourced}" == true ]]
}
