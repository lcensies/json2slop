# json2slop

> One JSON object in. One directory tree out. **Every** implementation, pick one.

[`json2dir`](https://github.com/alurm/json2dir) turns a JSON document into a tree of
files, directories, symlinks and executables. The idea was good enough that it now has
[six independent implementations](https://github.com/kitsunoff/awesome-json2dir) in six
languages — and six incompatible CLIs. One reads stdin and writes only to the current
directory. One takes `FILE OUTDIR` positionally. One has flags. One asks a language model.

`json2slop` is one CLI in front of all of them, and one container image that carries all of
them, because installing Rust nightly, Zig, Guile, .NET and Go to compare four
implementations of a 40-line conversion scheme is not a thing anyone should do.

```
$ json2slop --list-backends
BACKEND   BINARY                       SUPPORTS
rust      /opt/json2slop/rust/json2dir      -o
zig       /opt/json2slop/zig/json2dir       -o -n -v --no-clobber
scheme    /opt/json2slop/scheme/bin/json2dir -o
cs        /opt/json2slop/cs/json2dir-cs     -o
llm       /opt/json2slop/llm/json2llm       -o -n -v --no-clobber --llm-backend -m
dir2json  /opt/json2slop/dir2json/dir2json  reverse: -c -s --check

$ json2slop -b scheme -o out example-tree.json   # Guile does the writing
$ json2slop -b zig -n example-tree.json          # Zig, dry run
$ json2slop reverse out                          # tree back to JSON
```

## Backends

| `-b` | implementation | language | how it is driven |
| --- | --- | --- | --- |
| `rust` | [alurm/json2dir](https://github.com/alurm/json2dir) (the reference) | Rust | stdin, inside the target directory |
| `zig` | [71g3pf4c3/json2dir-zig](https://github.com/71g3pf4c3/json2dir-zig) | Zig | native flags (**default**) |
| `scheme` | [TheMaxMur/json2dir-scheme](https://github.com/TheMaxMur/json2dir-scheme) | Guile Scheme | stdin, inside the target directory |
| `cs` | [daniilvaino/json2dir-cs](https://github.com/daniilvaino/json2dir-cs) | C# | `FILE OUTDIR` |
| `llm` | [lcensies/json2llm](https://github.com/lcensies/json2llm) | Go + a model | native flags, plus `--llm-backend` |
| `reverse` | [71g3pf4c3/dir2json](https://github.com/71g3pf4c3/dir2json) | Rust | the other direction |

`-o` works everywhere: backends that only write to the current directory are run *inside*
the target. Options a backend cannot honour (`-n`, `-v`, `--no-clobber`) are a **usage
error naming the backend**, never silently dropped — a dropped `--no-clobber` would make a
destructive run look safe. Backend exit codes pass through unchanged; `1` is json2slop's own
usage error.

## Usage

```
Usage: json2slop [OPTIONS] [FILE]
       json2slop reverse [OPTIONS] [DIR]

  -b, --backend <B>      rust | zig | scheme | cs | llm   (default: zig)
  -o, --out <DIR>        Target directory (default: .). Created if missing.
  -n, --dry-run          Print the plan; write nothing.      [zig, llm]
  -v, --verbose          One line per entry while applying.  [zig, llm]
      --no-clobber       Fail instead of replacing entries.  [zig, llm]
      --llm-backend <B>  openai|pi|claude|codex|opencode|local|file:PATH  [llm]
  -m, --model <M>        Model for the llm backend's openai mode.         [llm]
      --list-backends    Print backends with their supported options.

reverse (dir2json): print the JSON reproducing DIR.
  -c, --compact   -s, --skip-special   --check FILE (exit 3 on drift)
```

`FILE` defaults to stdin; backends that need a path get stdin spooled to a temp file.

## Docker

```sh
docker build -t json2slop .

# apply into the current directory
docker run --rm -v "$PWD:/work" json2slop -b scheme -o /work tree.json
#   (tree.json must be inside the mount: ... json2slop -b scheme /work/tree.json)

# from stdin
cat tree.json | docker run --rm -i -v "$PWD/out:/work" json2slop -o /work

# tree → JSON, and drift check
docker run --rm -v "$PWD:/work" json2slop reverse /work/out
docker run --rm -v "$PWD:/work" json2slop reverse --check /work/tree.json /work/out
```

Multi-stage: Rust nightly (reference), Rust stable (`dir2json`), Zig 0.15, Go 1.25, .NET 10
and Guile each build in their own layer. The final image is `debian:bookworm-slim` plus
`guile-3.0` — the only backend that *is* source — with the C# backend published
self-contained so no .NET runtime ships. Every backend is cloned at a pinned SHA exposed as
a build argument:

```sh
docker build --build-arg REF_ZIG=<sha> -t json2slop .
```

Outside Docker the script works too: point `J2S_BIN_<BACKEND>` (or `J2S_PREFIX`) at
binaries you already have.

### The `llm` backend

`json2llm` needs either `OPENAI_API_KEY` or an agent CLI on `PATH` — neither is in the
image, since baking agent CLIs into a file-tree tool is its own kind of slop:

```sh
docker run --rm -e OPENAI_API_KEY -v "$PWD:/work" json2slop \
  -b llm --llm-backend openai -o /work/out /work/tree.json
```

`--llm-backend local` runs it with no model at all, which is also the only mode the test
harness will touch.

## Tests

`test/smoke.sh` is the cross-backend fixture harness — the thing
awesome-json2dir's Wanted list asks for. It applies each fixture with every backend into a
fresh directory and compares the trees using `dir2json` as the oracle (its output is
deterministic: sorted keys, no mtimes), then checks the refusal path, exit-code
propagation, dry-run inertness and stdin spooling.

```sh
docker run --rm --entrypoint /opt/json2slop/share/smoke.sh json2slop
```

Set `J2S_TEST_LLM=1` to include the `llm` backend (needs credentials, and it is
non-deterministic by design).

## The conversion scheme

Unchanged from upstream, which is the entire point:

| JSON | filesystem entry |
| --- | --- |
| object | directory, populated recursively |
| string | regular file with exactly that content |
| `["link", "target"]` | symlink to `target` |
| `["script", "content"]` | file with the executable bit set |

Backends differ in the margins — clobber policy, atomicity, symlink handling, whether a
dry run exists — and those differences are documented by each upstream. json2slop does not
paper over them; it lets you run the same manifest through each one and look.
