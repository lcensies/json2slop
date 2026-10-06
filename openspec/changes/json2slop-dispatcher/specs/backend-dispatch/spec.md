# backend-dispatch Specification

## Purpose

Provide one CLI, `json2slop`, that materializes a `json2dir`-scheme JSON document as a
directory tree using any of the known independent implementations as an interchangeable
backend, and reads a tree back as JSON in the reverse direction.

## Requirements

### Requirement: Unified command line

The CLI SHALL accept `json2slop [OPTIONS] [FILE]` where `FILE` is a JSON document
(`-` or omitted means stdin), with options `-b/--backend <B>`, `-o/--out <DIR>`,
`-n/--dry-run`, `-v/--verbose`, `--no-clobber`, `-h/--help`, `-V/--version`,
and SHALL exit `1` on usage errors.

#### Scenario: Default backend
- **WHEN** `json2slop tree.json` is run with no `-b`
- **THEN** the `zig` backend is used, because it is the only backend that honours every
  option in the unified interface

#### Scenario: Unknown backend
- **WHEN** `-b potato` is given
- **THEN** the run exits `1` and stderr lists the valid backend names

#### Scenario: Backend list
- **WHEN** `json2slop --list-backends` is run
- **THEN** each backend name is printed with the options it supports, and the exit code is `0`

### Requirement: Backend coverage

The CLI SHALL support every implementation listed by awesome-json2dir as a backend:
`rust` (alurm/json2dir), `zig` (json2dir-zig), `scheme` (json2dir-scheme),
`cs` (json2dir-cs), `llm` (json2llm), and `dir2json` for the reverse direction.

#### Scenario: Every backend materializes the fixture
- **WHEN** the reference fixture is applied with each of `rust`, `zig`, `scheme`, `cs`
  into separate empty target directories
- **THEN** every run exits `0` and all resulting trees are byte-identical as reported by
  `dir2json`

### Requirement: Per-backend argument translation

The CLI SHALL translate the unified options into each backend's native invocation:
flag-taking backends are invoked directly; backends that read stdin and write to the
current working directory are invoked with the target directory as cwd and the document
on stdin; positional-argument backends receive the document path and target directory as
arguments.

#### Scenario: cwd-only backend with an output directory
- **WHEN** `-b scheme -o out tree.json` is run
- **THEN** `out` is created if missing, the backend runs with `out` as its working
  directory, and the document is delivered on its stdin

#### Scenario: Document arriving on stdin for a stdin-incapable backend
- **WHEN** a document is piped to `json2slop -b cs` which requires a file path
- **THEN** the document is spooled to a temporary file, the backend is given that path,
  and the temporary file is removed on exit

### Requirement: Unsupported options are refused, never ignored

WHEN an option is requested that the selected backend cannot honour, the CLI SHALL exit
`1` with a message naming both the option and the backend, and SHALL NOT run the backend.

#### Scenario: Dry run on a backend without one
- **WHEN** `-b rust -n tree.json` is run and the `rust` backend has no dry-run mode
- **THEN** the run exits `1`, stderr says the `rust` backend does not support
  `--dry-run`, and nothing is written

#### Scenario: Honoured option passes through
- **WHEN** `-b zig -n tree.json` is run
- **THEN** the backend's own dry-run output is produced on stdout and the filesystem is
  untouched

### Requirement: LLM backend selection

The CLI SHALL expose the `llm` backend's own model backend through
`--llm-backend <openai|pi|claude|codex|opencode|local|file:PATH>` and a model override
through `-m/--model`, and SHALL reject those options for every other backend.

#### Scenario: Sub-backend passthrough
- **WHEN** `-b llm --llm-backend local tree.json` is run
- **THEN** `json2llm -b local` performs the run, with no credentials required

#### Scenario: Sub-backend on the wrong backend
- **WHEN** `-b zig --llm-backend local` is given
- **THEN** the run exits `1` naming `--llm-backend` as invalid for `zig`

### Requirement: Reverse direction

The CLI SHALL provide `json2slop reverse [OPTIONS] [DIR]` that prints the JSON document
reproducing `DIR`, supporting `-c/--compact`, `-s/--skip-special` and
`--check FILE` for drift detection.

#### Scenario: Roundtrip
- **WHEN** a fixture is applied with any backend and `json2slop reverse` is run against
  the result
- **THEN** the printed document describes the same tree as the fixture

#### Scenario: Drift
- **WHEN** `json2slop reverse --check tree.json out` is run against a tree that differs
- **THEN** a per-path mismatch report is printed and the exit code is `3`

### Requirement: Exit code propagation

The CLI SHALL propagate the selected backend's exit status unchanged, reserving `1` for
its own usage errors.

#### Scenario: Invalid document
- **WHEN** a document whose root is an array is applied with `-b zig`
- **THEN** the exit code is the backend's own invalid-input code, not `1`
