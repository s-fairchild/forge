---
name: linting-code
description: >
  Lints shell scripts under hack/ (hack/bin, hack/lib — excluding every git submodule under
  hack/) using ShellCheck per this repo's .shellcheckrc. Use whenever checking code quality or
  fixing lint errors in this tree. Does not cover hack/vendor/bash-logger/ or
  hack/vendor/bashkit/ — both are independently-versioned git submodules with their own more
  specific linting-code skills, and both are excluded from `lint-hack`; use each submodule's
  own skill/toolchain for files under it. hack/vendor/bashkit/ also carries a linting-code
  skill for work done directly in that submodule as a standalone repo (no forge
  Makefile/`.shellcheckrc` available there).
---

# Linting Code (hack/)

Adapted from `hack/vendor/bash-logger/.claude/skills/linting-code/`. That skill assumes
bash-logger's own toolchain (pre-commit, markdownlint, a test runner) — none of which exist
at the forge repo level, so this version reflects what's actually here instead of reusing that
one wholesale.

## Tools and where configuration lives

| Tool       | Checks                                          | Config                                                                            |
| ---------- | ------------------------------------------------ | ---------------------------------------------------------------------------------- |
| ShellCheck | Shell syntax, quoting, portability, common bugs | repo-root `.shellcheckrc` (`external-sources=true`, `source-path=SCRIPTDIR`, `check-sourced=true`) |

Forge has **no pre-commit config and no markdownlint config** — unlike the bash-logger
submodule. ShellCheck runs as a plain host binary via two root `Makefile` targets
(`lint-hack`, `lint-hack-file`). The bats suites (`make test`) only cover a few `hack/bin` scripts so
far, so "does it lint clean" is only half the check — see "Confirm it actually behaves" below.

`lint-hack` excludes **every git submodule under `hack/`** (currently `hack/vendor/bashkit`
and `hack/vendor/bash-logger`), derived at Makefile-eval time from `.gitmodules` rather than
hardcoded — a future submodule added under `hack/` is excluded automatically, no Makefile edit
needed. Non-submodule vendored code (a plain directory under `hack/vendor/`, not a submodule) is
still linted. `lint-hack` also runs ShellCheck once per file
in parallel across `nproc` jobs via `xargs -P`, printing each `shellcheck <file>` invocation to
stderr as it's dispatched (`xargs -t`) so a long run shows visible progress instead of sitting
silent.

## Commands

Run from the **repo root** (the root `Makefile`'s targets are always invoked directly, never
via `make -C`, which is what keeps cwd at repo root — see the note on sourcing conventions
below). `.shellcheckrc`'s `source-path=SCRIPTDIR` + `check-sourced=true` mean ShellCheck
follows `source`/`.` statements relative to each script's own directory (this resolution is
cwd-independent — verified by diffing output run from repo root vs. from `hack/`), but whether
that resolution is *correct* still depends on the sourcing conventions in `CLAUDE.md` ("Logging
and Vendored Dependencies"): `hack/lib/*` and `hack/bin/*` source files relative to themselves
(`${BASH_SOURCE[0]%/*}/...`), and files under `hack/vendor/bashkit/` `import` theirs by name. The
scripts still assume they run from repo root (e.g. `hack/etc/kube-manifests-gen.env` finds `pkg/`
from the CWD).

### Single file

```bash
make lint-hack-file FILE=hack/bin/k3s-tokens-generate.sh
```

### Everything under hack/, excluding its git submodules

```bash
make lint-hack
```

(`hack/vendor/bash-logger/` and `hack/vendor/bashkit/` are independently versioned and each
has its own `linting-code` skill — use those for files under them, not this target.)

### Confirm it actually behaves, not just parses

After ShellCheck passes, run `make test` if the script has a suite (`test/bin/<name>.bats` or
`test/lib/<dir>/<file>.bats`; see `test/test_helper.bash` for adding one), and validate by actually
sourcing or running the script from repo root — e.g. for a lib file, source
`hack/vendor/bashkit/local/lib/bashkit/os/bk-bootstrap.sh` first and then
`. hack/lib/kubevirt/kubevirt.sh` (twice, to check it changes nothing), or exercise a
`hack/bin/*.sh` entry point's `-h`/actual invocation. Without the bootstrap, a bashkit library's
`import` lines run ImageMagick's `import(1)` and hang.

## Key rules — write clean code from the start

Based on [Google's Shell Style Guide](https://google.github.io/styleguide/shellguide.html).
This repo has no POSIX-portability requirement — everything under `hack/` is bash-only
(`#!/bin/bash`), so write to bash idioms directly rather than the lowest-common-denominator
POSIX subset.

* **Indentation**: 2 spaces, never tabs — the one exception is the body of a `<<-` here-document,
  where a leading tab is permitted so the terminator can be indented.
* **Line length**: soft-wrap around 80 columns. Split long `podman run`/similar option strings
  across lines (one flag per line, `\` continuation) or build them as a quoted array instead of
  one long string.
* **Quoting**: quote every expansion; prefer `"${var}"` over `"$var"` (brace-delimit unless it's
  a single-character shell special like `$?`/`$#`/`$$`/`$!`, which don't need braces). Use a
  `local -a`/`declare -a` array (expanded `"${arr[@]}"`, quoted) for any list of command
  options/flags rather than an unquoted string — don't reach for
  `# shellcheck disable=SC2068` as a substitute for quoting the array correctly.
* **Conditionals**: `[[ ]]` everywhere, not `[ ]`/`test`/`/usr/bin/[` — `[[ ]]` avoids word
  splitting/pathname expansion and supports `==`/regex matching. Use `-z`/`-n` for string
  emptiness checks, `==` for string equality, `(( ))` for numeric comparisons.
* **Command substitution**: `$(...)`, never backticks.
* **Arithmetic**: `(( ))` or `$(( ))` only — never `let` or `$[ ]`, and never `expr`.
* **No `eval`**, no shell aliases (use a function instead).
* **Naming**: lowercase `snake_case` for functions and variables; filenames lowercase with
  underscores. Constants and anything exported are `SCREAMING_SNAKE_CASE`, declared at the top
  of the file with `readonly`/`export` (or `declare -r`/`declare -rx`). Function-local variables
  use `local` (add `-r`/`-a`/`-A`/`-i` where it fits); split `local x` from `x=$(...)` so a
  command substitution's exit status isn't masked (see SC2155 below).
* **File header**: every file starts with a one-line description of what it contains.
* **Function comments**: required for every non-trivial function and for anything in a `hack/lib/*`
  library file (even a small one) — Description, Globals used/modified, Arguments, Outputs, and
  Return value. A short, self-evident helper (e.g. a one-line `usage_*()`) can skip this.
* **`main`**: a script with more than one function defines `main()` and calls `main "$@"` as the
  last line — already the convention for every `hack/bin/*.sh` entry point.
* Every sourced file (`hack/lib/*`, `hack/etc/*.env`, `hack/vendor/bashkit/*`) can be sourced any
  number of times without changing anything. There are no `__*_SOURCED` guard variables: define
  each constant only if it isn't already (`[[ -v X ]] || readonly X="..."`; for an array, test
  with `declare -p` and declare it with `declare -g`), and keep the top level to sourcing,
  function definitions, and constants. Load a file's own dependencies rather than assuming a
  caller already did. `hack/bin/*.sh` entry points source bashkit's `os/bk-bootstrap.sh` before
  anything from bashkit — preserve this when adding new files.
* Shell **libraries** (`hack/lib/**/*.sh`) must not be executable (`chmod -x`) — only
  `hack/bin/*.sh` entry points are. This also signals at a glance which files are meant to be
  sourced vs. run.
* When suppressing a ShellCheck warning, add a reason. `# shellcheck disable=SCXXXX -- reason`
  is **not** valid directive syntax and fails to parse (SC1072/SC1073) — ShellCheck only accepts
  `key=value` pairs after `# shellcheck`. Use a second `#` to start a plain trailing comment
  instead:

  ```bash
  # shellcheck disable=SC2034  # consumed by a script that sources this file
  ```

## Interpreting failures

Format: `file.sh:LINE:COL: severity: message [SCXXX]`. Look up unknown codes at
`https://www.shellcheck.net/wiki/SCXXX`.

Common in this repo:

| Code   | Cause                                        | Fix                                                          |
| ------ | --------------------------------------------- | -------------------------------------------------------------- |
| SC2086 | Unquoted variable                            | Wrap in `"$var"`                                              |
| SC1091 | Can't follow a sourced file                  | Usually resolved by `external-sources=true`; if it still fires, check that the `# shellcheck source=` directive's path exists relative to the file it is in |
| SC2155 | Combined `local`/assign masking exit status  | Split: `local x; x=$(...)`                                    |
