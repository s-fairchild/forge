---
name: linting-code
description: >
  Lints shell scripts under hack/ (hack/bin, hack/lib, hack/vendor/bashkit) using ShellCheck
  per this repo's .shellcheckrc. Use whenever checking code quality or fixing lint errors in
  this tree. Does not cover hack/vendor/bash-logger/, which has its own more specific
  linting-code skill — that one wins for files under it.
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

* Follow **POSIX Utility Conventions** (Ch. 12) for any script that accepts CLI options: single-
  character options preceded by `-`, options before operands, `--` terminates options, option-
  arguments adjacent or as the next arg, no optional option-arguments.
* Follow **POSIX Shell Command Language** (Ch. 2) for quoting, word expansion, command
  substitution, arithmetic expansion, and control flow.
* 4-space indentation, no tabs — matches existing `hack/bin`/`hack/lib` scripts.
* Quote all variable expansions: `"$var"`, not `$var`.
* `[[ ]]` for bash conditionals in bash-only files (most of `hack/`); reserve `[ ]` for scripts
  where POSIX portability is explicitly required.
* `$(...)`, not backticks.
* Every sourced lib file (`hack/lib/*`, `hack/vendor/bashkit/*`) guards against double-inclusion
  with `declare -r __<lib>_sourced="true"` and re-sources its own dependencies rather than
  assuming a caller already loaded them — preserve this when adding new lib files.
* When suppressing a ShellCheck warning, add a reason:

  ```bash
  # shellcheck disable=SC2034 -- consumed by a script that sources this file
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
