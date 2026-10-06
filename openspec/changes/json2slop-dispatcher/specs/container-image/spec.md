# container-image Specification

## Purpose

Ship every `json2dir` implementation, their runtimes and the `json2slop` dispatcher as one
container image, so that using six languages costs the user one `docker run`.

## Requirements

### Requirement: Single image carries every backend

The image SHALL contain executables for all backends plus `json2slop` on `PATH`, and its
entrypoint SHALL be `json2slop`.

#### Scenario: Backends present
- **WHEN** `docker run <image> --list-backends` is run
- **THEN** every backend is listed and reported as available

#### Scenario: Default invocation
- **WHEN** a document is piped to `docker run -i -v "$PWD/out:/work" <image> -o /work`
- **THEN** the tree is materialized in the mounted directory

### Requirement: Toolchains stay out of the final layer

The image SHALL be built multi-stage, with each backend compiled or staged in its own
builder, and the final stage SHALL receive only the backend artifacts plus the runtimes
needed to execute them.

#### Scenario: No compilers shipped
- **WHEN** the final image is inspected for `cargo`, `zig`, `go` and the .NET SDK
- **THEN** none of them is present

### Requirement: Pinned backend sources

Every backend source SHALL be fetched at a pinned git ref declared as a build argument, so
a rebuild is reproducible and a backend can be bumped without editing build logic.

#### Scenario: Overriding a ref
- **WHEN** the image is built with a build argument overriding one backend's ref
- **THEN** only that backend is rebuilt from the given ref

### Requirement: Cross-backend fixture harness

The repository SHALL provide a harness that applies the same fixtures with every
non-LLM backend and fails if the resulting trees differ, using `dir2json` as the oracle.

#### Scenario: Agreement
- **WHEN** the harness runs inside the image
- **THEN** it reports one line per backend and exits `0` when all trees match

#### Scenario: Disagreement
- **WHEN** one backend produces a different tree
- **THEN** the harness prints the differing backend and the diff, and exits non-zero

#### Scenario: LLM backend excluded by default
- **WHEN** the harness runs without credentials
- **THEN** the `llm` backend is skipped with a notice rather than failing the run
