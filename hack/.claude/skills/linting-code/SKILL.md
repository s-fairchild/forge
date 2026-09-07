---
name: linting-code
description: >
  Lints shell scripts under hack/ (hack/bin, hack/lib, hack/vendor/bashkit) using ShellCheck
  per this repo's .shellcheckrc. Use whenever checking code quality or fixing lint errors in
  this tree. Does not cover hack/vendor/bash-logger/, which has its own more specific
  linting-code skill — that one wins for files under it. hack/vendor/bashkit/ also carries its
  own linting-code skill for work done directly in that submodule as a standalone repo (no
  forge Makefile/`.shellcheckrc` available there); this one still applies — and is the
  simpler path — when linting bashkit files from within a forge checkout, since `lint-hack`
  already includes them.
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
(`lint-hack`, `lint-hack-file`); there is no automated test suite in this repo (per
`CLAUDE.md`), so "does it lint clean" is only half the check — see "Confirm it actually
behaves" below.

## Commands

Run from the **repo root** (the root `Makefile`'s targets are always invoked directly, never
via `make -C`, which is what keeps cwd at repo root — see the note on sourcing conventions
below). `.shellcheckrc`'s `source-path=SCRIPTDIR` + `check-sourced=true` mean ShellCheck
follows `source`/`.` statements relative to each script's own directory (this resolution is
cwd-independent — verified by diffing output run from repo root vs. from `hack/`), but whether
that resolution is *correct* still depends on the repo's two sourcing conventions (see
`CLAUDE.md` "Logging and Vendored Dependencies") — files under `hack/vendor/bashkit/` source
siblings relative to their own location, everything else (`hack/lib/*`, `hack/bin/*`)
hardcodes paths relative to repo root, which is why those must be *run* from there (linting
itself doesn't require it, but stay consistent).

### Single file

```bash
make lint-hack-file FILE=hack/bin/k3s-tokens-generate.sh
```

### Everything under hack/, excluding the bash-logger submodule

```bash
make lint-hack
```

(`hack/vendor/bash-logger/` is independently versioned and has its own `linting-code` skill —
use that one for files under it, not this target.)

### Confirm it actually behaves, not just parses

There's no automated test suite here. After ShellCheck passes, validate by actually sourcing
or running the script from repo root — e.g. `source hack/lib/ignition/ignition.sh` for a lib
file, or exercising a `hack/bin/*.sh` entry point's `-h`/actual invocation.

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
* Every sourced lib file (`hack/lib/*`, `hack/vendor/bashkit/*`) guards against double-inclusion
  with `declare -r __hack_lib_<path>_sourced="true"`, named after the file's path under
  `hack/lib/` — `<dir>_<filename>` (e.g. `hack/lib/ignition/butane.sh` →
  `__hack_lib_ignition_butane_sourced`), but drop the duplicate segment when the filename
  already starts with (or equals) the directory name, to avoid stuttering (e.g.
  `hack/lib/podman/podman-secret.sh` → `__hack_lib_podman_secret_sourced`, not
  `__hack_lib_podman_podman_secret_sourced`; `hack/lib/ignition/ignition.sh` →
  `__hack_lib_ignition_sourced`). Re-source a file's own dependencies rather than assuming a
  caller already loaded them — preserve this when adding new lib files.
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
| SC1091 | Can't follow a sourced file                  | Usually resolved by `external-sources=true`; if it still fires, confirm you're running from repo root (or, for `hack/vendor/bashkit/`, that the sibling file exists relative to the sourcing file itself) |
| SC2155 | Combined `local`/assign masking exit status  | Split: `local x; x=$(...)`                                    |
