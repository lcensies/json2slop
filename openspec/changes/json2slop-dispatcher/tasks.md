# Tasks

## 1. Dispatcher

- [ ] 1.1 Write `json2slop` (POSIX sh): option parsing for `-b -o -n -v --no-clobber -m --llm-backend -h -V --list-backends`, `FILE`/`-`/stdin, and the `reverse` subcommand.
- [ ] 1.2 Add the per-backend capability table and the central refusal check (exit 1, naming option and backend).
- [ ] 1.3 Add backend adapters: direct-flags (`zig`, `llm`), stdin+cwd (`rust`, `scheme`), positional (`cs`), reverse (`dir2json`); resolve binaries from `/opt/json2slop/<b>/...` with `J2S_BIN_<B>` overrides.
- [ ] 1.4 Normalize stdin↔file with `mktemp` + `trap` cleanup; propagate backend exit status.

## 2. Image

- [ ] 2.1 Write the multi-stage `Dockerfile`: builder stages for rust-nightly (reference), rust-stable (dir2json), zig 0.15, go 1.25, dotnet 10 (self-contained single file), scheme (`make install PREFIX`).
- [ ] 2.2 Final `debian:bookworm-slim` stage: `guile-3.0` + `ca-certificates`, copy artifacts to `/opt/json2slop/`, install `json2slop` to `/usr/local/bin`, `ENTRYPOINT ["json2slop"]`, `WORKDIR /work`.
- [ ] 2.3 Declare one `ARG <NAME>_REF` per backend and clone at that ref.

## 3. Fixtures and harness

- [ ] 3.1 Add `example-tree.json` (the scheme's canonical fixture) and an edge-case fixture (empty object, nested dirs, unicode content).
- [ ] 3.2 Write `test/smoke.sh`: per backend × fixture, apply into a fresh temp dir, compare `dir2json -c` output across backends, print one line per backend, non-zero on divergence; skip `llm` unless `J2S_TEST_LLM`.
- [ ] 3.3 Verify the refusal path and exit-code propagation in the same script (`-b rust -n` → exit 1; bad document → backend's exit code).

## 4. Docs and verification

- [ ] 4.1 `README.md`: the premise, backend table with supported options, `docker run` recipes (stdin, `-v` mount, reverse, drift check), LLM backend credentials note.
- [ ] 4.2 Build the image and run `test/smoke.sh` inside it; record which backends agree.
