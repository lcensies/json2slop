#!/bin/sh
# Cross-backend fixture harness: every backend must produce the same tree.
# dir2json is the oracle — deterministic output (sorted keys, no mtimes, no
# permission noise beyond the exec bit), so comparing its output compares trees.
set -u

J2S=${J2S:-json2slop}
SHARE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
FIXTURES=${*:-$SHARE/example-tree.json $SHARE/edge-tree.json}
BACKENDS='rust zig scheme cs'
[ -n "${J2S_TEST_LLM:-}" ] && BACKENDS="$BACKENDS llm"

fail=0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

for fx in $FIXTURES; do
	[ -r "$fx" ] || { echo "missing fixture $fx"; fail=1; continue; }
	echo "== $(basename "$fx")"
	ref= refb=
	for b in $BACKENDS; do
		out=$work/$b
		rm -rf "$out"
		mkdir -p "$out"
		"$J2S" -b "$b" -o "$out" "$fx" >"$work/log" 2>&1; st=$?
		if [ "$st" -ne 0 ]; then
			echo "  $b: FAIL (exit $st)"; sed 's/^/    /' "$work/log"; fail=1; continue
		fi
		got=$("$J2S" reverse -c "$out") || { echo "  $b: FAIL (dir2json)"; fail=1; continue; }
		if [ -z "$refb" ]; then
			ref=$got refb=$b
			echo "  $b: ok (reference)"
		elif [ "$got" = "$ref" ]; then
			echo "  $b: ok"
		else
			echo "  $b: DIFFERS from $refb"
			printf '    %s: %s\n    %s: %s\n' "$refb" "$ref" "$b" "$got"
			fail=1
		fi
	done
	# The fixture itself is the desired state: drift-check the reference tree.
	if [ -n "$refb" ] && ! "$J2S" reverse --check "$fx" "$work/$refb" >"$work/log" 2>&1; then
		echo "  drift vs fixture ($refb):"; sed 's/^/    /' "$work/log"; fail=1
	fi
done

echo '== behaviour'

# An option the backend cannot honour is a usage error, and writes nothing.
rm -rf "$work/refuse"; mkdir -p "$work/refuse"
"$J2S" -b rust -n -o "$work/refuse" "$SHARE/example-tree.json" >"$work/log" 2>&1; st=$?
left=$(ls -A "$work/refuse" | wc -l)
if [ "$st" -eq 1 ] && [ "$left" -eq 0 ]; then
	echo '  refusal (-b rust -n): ok'
else
	echo "  refusal (-b rust -n): FAIL (exit $st, $left entries written)"; sed 's/^/    /' "$work/log"; fail=1
fi

# Backend exit codes pass through: json2dir-zig exits 2 on an invalid document.
echo '[]' >"$work/bad.json"
"$J2S" -b zig -o "$work/bad" "$work/bad.json" >"$work/log" 2>&1; st=$?
if [ "$st" -eq 2 ]; then
	echo '  exit-code propagation: ok'
else
	echo "  exit-code propagation: FAIL (got $st, wanted the backend's 2)"; fail=1
fi

# A dry run creates nothing at all, not even the target directory.
rm -rf "$work/dry"
"$J2S" -b zig -n -o "$work/dry" "$SHARE/example-tree.json" >/dev/null 2>&1
if [ -e "$work/dry" ]; then echo '  dry run: FAIL (target created)'; fail=1; else echo '  dry run: ok'; fi

# stdin spooling for a backend that only takes a file path.
rm -rf "$work/pipe" "$work/want"; mkdir -p "$work/pipe" "$work/want"
"$J2S" -b zig -o "$work/want" "$SHARE/example-tree.json" >/dev/null 2>&1
want=$("$J2S" reverse -c "$work/want")
if "$J2S" -b cs -o "$work/pipe" <"$SHARE/example-tree.json" >"$work/log" 2>&1 &&
	[ "$("$J2S" reverse -c "$work/pipe")" = "$want" ]; then
	echo '  stdin → file-only backend: ok'
else
	echo '  stdin → file-only backend: FAIL'; sed 's/^/    /' "$work/log"; fail=1
fi

[ "$fail" -eq 0 ] && echo 'all backends agree' || echo 'DISAGREEMENT'
exit "$fail"
