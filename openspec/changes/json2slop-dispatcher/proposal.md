# Proposal

## Why

The `json2dir` conversion scheme (JSON object in, directory tree out) now has six
independent implementations across six languages — Rust, Zig, Guile Scheme, C#, Go+LLM,
plus the inverse `dir2json` — each with an incompatible CLI: some read stdin and write
only to the current directory, one takes positional `FILE OUTDIR`, one has flags, one
needs an API key. Nobody can install all of them, and nobody can compare them. `json2slop`
is one CLI and one container image that fronts all of them as selectable backends.

## What Changes

- New `json2slop` CLI: a unified, `json2dir-zig`-shaped interface
  (`-o DIR`, `-n`, `-v`, `--no-clobber`, `FILE`, `-` for stdin) that dispatches to a
  backend selected with `-b/--backend`.
- Backends (every entry in awesome-json2dir):
  `rust` (alurm/json2dir, reference), `zig` (json2dir-zig), `scheme` (json2dir-scheme),
  `cs` (json2dir-cs), `llm` (json2llm, with its own sub-backend via `--llm-backend`),
  and `dir2json` for the reverse direction.
- Per-backend capability adaptation: flags a backend cannot honour are a hard usage
  error naming the backend, never silently dropped. stdin/cwd-only backends are driven
  by a shim (`cd` into the target, feed the document on stdin).
- Reverse direction: `json2slop reverse [DIR]` → JSON on stdout, plus drift checking
  (`--check FILE`), via `dir2json`.
- A single Docker image carrying all backends and their runtimes, built multi-stage so
  no language toolchain lands in the final layer except the ones required at run time.
- A cross-backend smoke harness: apply the same fixture with every backend and assert the
  resulting trees are identical, using `dir2json` as the oracle. (This is the
  "test harness that checks every implementation against the same fixtures" from
  awesome-json2dir's Wanted list.)

## Capabilities

### New Capabilities
- `backend-dispatch`: the unified CLI, backend selection, per-backend argument
  translation and capability refusal, and the reverse direction.
- `container-image`: the multi-stage image that provides every backend, pinned
  backend sources, and the cross-backend fixture harness.

### Modified Capabilities

(none — greenfield project)

## Impact

- New repository contents: `json2slop` (POSIX sh), `Dockerfile`, `example-tree.json`,
  `test/smoke.sh`, `README.md`.
- External dependencies, all fetched at image build time at pinned refs:
  alurm/json2dir, 71g3pf4c3/json2dir-zig, TheMaxMur/json2dir-scheme,
  daniilvaino/json2dir-cs, lcensies/json2llm, 71g3pf4c3/dir2json.
- Runtime dependencies in the final image: Guile 3.0 (scheme), .NET runtime (cs),
  glibc. Rust/Zig/Go backends are static or glibc-linked binaries.
- The `llm` backend needs credentials or an agent CLI at run time; it is never
  exercised by the default smoke run.
