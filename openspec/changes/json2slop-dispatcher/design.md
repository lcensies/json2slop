# Design

## Context

Six upstream implementations, six CLIs, six toolchains. The dispatcher is argument
translation and nothing else — it must not reimplement the conversion scheme, because the
whole point is that the *upstream* implementation does the work.

## Decisions

### POSIX sh dispatcher, Docker-only distribution

The dispatcher is ~200 lines of POSIX `sh` with no build step, invoked as the image
entrypoint. A compiled dispatcher would buy real argument parsing we do not need: the
option set is fixed and tiny, and every real behaviour lives in the backend.

Backend paths are absolute under `/opt/json2slop/<backend>/` and each is overridable with
`J2S_BIN_<BACKEND>` so the script also runs on a host that has some backends installed.

### Capability matrix, enforced centrally

| backend | binary | invocation | `-o` | `-n` | `-v` | `--no-clobber` |
| --- | --- | --- | --- | --- | --- | --- |
| `rust` | `json2dir` (alurm) | stdin → cwd | via cwd | no | no | no |
| `zig` | `json2dir` (zig) | `[-o] [-n] [-v] [--no-clobber] FILE` | yes | yes | yes | yes |
| `scheme` | `json2dir` (guile) | stdin → cwd | via cwd | no | no | no |
| `cs` | `json2dir-cs` | `FILE OUTDIR` | yes | no | no | no |
| `llm` | `json2llm` | same flags as `zig`, plus `-b`/`-m` | yes | yes | yes | yes |
| `dir2json` | `dir2json` | `[-c] [-s] [--check F] DIR` | n/a | n/a | n/a | n/a |

One table per backend in the script (`caps` string), one check loop. An unsupported option
is a usage error naming option and backend — not a silent drop, which would make a
`--no-clobber` run look safe when it was destructive.

`-o` is universal: for cwd-only backends the directory is created and `cd`'d into, which is
exactly what upstream's own docs tell users to do by hand.

Default backend is `zig`: it is the only one honouring every unified option, so the default
never trips the refusal path.

### stdin/file normalization

Unified CLI accepts a file or stdin; backends split on which they can take. The script
spools stdin to a temp file once (`mktemp`, `trap` cleanup) when the backend needs a path,
and feeds a file on stdin via redirection when the backend needs stdin. One normalization
point, so each backend adapter is a single `exec`-shaped line.

### Image: one builder per language, nothing shared

| stage | base | produces |
| --- | --- | --- |
| rust-nightly | `rustlang/rust:nightly-bookworm` | `json2dir` (alurm — its `rust-toolchain.toml` pins nightly) |
| rust-stable | `rust:1-bookworm` | `dir2json` |
| zig | `debian:bookworm-slim` + zig 0.15 tarball | `json2dir` (zig, static) |
| go | `golang:1.25-bookworm` | `json2llm` |
| dotnet | `mcr.microsoft.com/dotnet/sdk:10.0` | `json2dir-cs`, self-contained single file |
| scheme | `debian:bookworm-slim` | `make install PREFIX=/opt/json2slop/scheme` (source + shim) |
| final | `debian:bookworm-slim` + `guile-3.0` | all of the above + `json2slop` |

Two Rust stages because the reference pins a nightly toolchain and `dir2json` pins stable;
sharing one stage would mean building the reference on the wrong channel.

`dotnet publish --self-contained -p:PublishSingleFile=true` instead of installing the .NET
runtime in the final layer: one ~70 MB binary, no SDK, no runtime package. Guile is the one
real runtime dependency left, because the Scheme port *is* source.

Every repo is cloned at a ref passed as `ARG <NAME>_REF`, so a bump is a build argument and
layer caching stays per-backend.

### Fixture harness as the project's test

`test/smoke.sh` applies each fixture with every non-LLM backend into its own temp directory
and compares `dir2json -c` output across backends. `dir2json` is the oracle: it is
deterministic (sorted keys, no mtimes) so byte-comparing its output is a tree comparison.
Divergences that are upstream-documented (e.g. the reference reuses an existing directory
where the Zig port replaces it) are confined to fixtures applied into empty directories, so
the harness tests the scheme, not the clobber policies.

The `llm` backend is skipped unless `J2S_TEST_LLM` is set, since it needs credentials or an
agent CLI and is explicitly non-deterministic.

## Risks

- **Upstream CLIs drift.** Pinned refs mean a drift shows up at bump time, with the harness
  as the detector.
- **Image size** ~1 GB, dominated by the self-contained .NET binary. Acceptable: the whole
  premise is six languages in one place.
- **The reference's nightly pin** can break on any given nightly. The ref is pinned; if a
  nightly image breaks, pin the nightly date tag too.
