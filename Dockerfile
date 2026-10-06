# syntax=docker/dockerfile:1
# json2slop: every json2dir implementation, one image, one CLI.
# Each backend is cloned at a pinned ref and built in its own stage. A backend
# that fails to build is NOT a build failure: the stage stages whatever it got
# into /out, and a missing binary degrades to "backend not installed" at run
# time. Upstream breakage is upstream's problem; the dispatcher stays usable.

ARG REF_RUST=b2072fb5515a603024c123297b27dcaabfdf098a
ARG REF_ZIG=bbc33644d49429cec63cb505029a4e4e3c2b1eda
ARG REF_SCHEME=8629f91bb028f8aa61534375066e83de6c431e98
ARG REF_CS=0fe4882d033cbb65b1489b0dc59727efcff386e7
ARG REF_LLM=14cd2aae8588931c72e3c2c436b9bf2b71e7aa47
ARG REF_DIR2JSON=f6ba4be8470938117f40842461b66009b967d68d
ARG ZIG_VERSION=0.15.1

# --- rust: the reference implementation ---
FROM rustlang/rust:nightly-bookworm AS build-rust
ARG REF_RUST
# The pinned rust-toolchain.toml also demands miri/rust-analyzer components that
# are absent from some nightlies; the image's own nightly builds the source fine.
RUN mkdir /out && git clone https://github.com/alurm/json2dir /src \
 && cd /src && git checkout "$REF_RUST" && rm -f rust-toolchain.toml \
 && { cargo build --release && cp target/release/json2dir /out/ || echo "BACKEND rust FAILED TO BUILD" >&2; } \
 && touch /out/.keep

# --- rust (stable): the inverse tool, also the harness oracle ---
FROM rust:1-bookworm AS build-dir2json
ARG REF_DIR2JSON
RUN mkdir /out && git clone https://github.com/71g3pf4c3/dir2json /src \
 && cd /src && git checkout "$REF_DIR2JSON" \
 && { cargo build --release && cp target/release/dir2json /out/ || echo "BACKEND dir2json FAILED TO BUILD" >&2; } \
 && touch /out/.keep

# --- zig: static, no libc ---
FROM debian:bookworm-slim AS build-zig
ARG REF_ZIG
ARG ZIG_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git xz-utils && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" \
      | tar -xJ -C /opt \
 && ln -s "/opt/zig-x86_64-linux-${ZIG_VERSION}/zig" /usr/local/bin/zig
# Upstream's build.zig.zon carries a hand-written fingerprint zig rejects; zig
# names the correct one, so take it from zig rather than hardcoding a value that
# changes with the package name or paths.
RUN mkdir /out && git clone https://github.com/71g3pf4c3/json2dir-zig /src \
 && cd /src && git checkout "$REF_ZIG" \
 && want=$(zig build 2>&1 | sed -n 's/.*use this value: \(0x[0-9a-f]*\).*/\1/p' | head -1) \
 && if [ -n "$want" ]; then sed -i "s/\.fingerprint = 0x[0-9a-f]*/.fingerprint = $want/" build.zig.zon; fi \
 && { zig build -Doptimize=ReleaseSafe && cp zig-out/bin/json2dir /out/ || echo "BACKEND zig FAILED TO BUILD" >&2; } \
 && touch /out/.keep

# --- go: the LLM backend ---
FROM golang:1.25-bookworm AS build-llm
ARG REF_LLM
RUN mkdir /out && git clone https://github.com/lcensies/json2llm /src \
 && cd /src && git checkout "$REF_LLM" \
 && { CGO_ENABLED=0 go build -o /out/json2llm . || echo "BACKEND llm FAILED TO BUILD" >&2; } \
 && touch /out/.keep

# --- dotnet: self-contained single file, so no .NET runtime in the final layer ---
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build-cs
ARG REF_CS
RUN mkdir /out && git clone https://github.com/daniilvaino/json2dir-cs /src \
 && cd /src && git checkout "$REF_CS" \
 && { dotnet publish json2dir/json2dir.csproj -c Release -r linux-x64 \
        --self-contained true -p:PublishSingleFile=true -o /pub \
      && mv /pub/json2dir /out/json2dir-cs || echo "BACKEND cs FAILED TO BUILD" >&2; } \
 && touch /out/.keep

# --- scheme: source plus a shim; Guile is the runtime ---
FROM debian:bookworm-slim AS build-scheme
ARG REF_SCHEME
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates git make && rm -rf /var/lib/apt/lists/*
# GUILE is baked into the installed shim, and Debian ships the binary as guile-3.0.
RUN mkdir -p /out/bin && git clone https://github.com/TheMaxMur/json2dir-scheme /src \
 && cd /src && git checkout "$REF_SCHEME" \
 && { make install PREFIX=/out GUILE=guile-3.0 || echo "BACKEND scheme FAILED TO BUILD" >&2; } \
 && touch /out/.keep

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates guile-3.0 && rm -rf /var/lib/apt/lists/*
COPY --from=build-rust     /out/ /opt/json2slop/rust/
COPY --from=build-zig      /out/ /opt/json2slop/zig/
COPY --from=build-cs       /out/ /opt/json2slop/cs/
COPY --from=build-llm      /out/ /opt/json2slop/llm/
COPY --from=build-dir2json /out/ /opt/json2slop/dir2json/
COPY --from=build-scheme   /out/ /opt/json2slop/scheme/
COPY json2slop /usr/local/bin/json2slop
COPY example-tree.json test/ /opt/json2slop/share/
RUN chmod +x /usr/local/bin/json2slop /opt/json2slop/share/smoke.sh
WORKDIR /work
ENTRYPOINT ["json2slop"]
CMD ["--help"]
