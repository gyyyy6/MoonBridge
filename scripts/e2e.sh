#!/usr/bin/env bash
# Proves the whole chain on a real package: `.mbti` -> stubs -> callable module
# -> generated guest -> wasm -> Python, then measures what the boundary costs.
#
#   1. build the generator as js
#   2. generate every stub, a callable module for the bound packages, and the
#      guest half of the binding — all from one plan
#   3. build that guest as wasm
#   4. drive the generated Python against it: call functions, construct
#      objects, read and write fields, pass a list / a dict / a callable, catch
#      a typed error
#   5. run the 100k-call benchmark, which exits non-zero on a leak
#   6. build a wheel through PEP 517, pip install it into a throwaway venv, and
#      use it from outside the repository
#
# Step 2 writes into `src/guest_gen`, so a checkout that never runs this script
# still builds; running it is how that directory is produced.
#
# Usage:
#   scripts/e2e.sh                # default 100k calls
#   BENCH_CALLS=20000 scripts/e2e.sh
#
# Requirements: moon, node, python + wasmtime (`pip install wasmtime`).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="${GEN_OUT:-$ROOT/_gen}"
WASM="$ROOT/_build/wasm/release/build/guest_gen/guest_gen.wasm"
# `callbacks` is this repository's own package: it exists so the callback
# channel has something that actually calls a function value, which nothing in
# the standard library does.
BOUND="moonbitlang/core/json,moonbitlang/core/builtin,moonbitlang/core/lexbuf,gyyyy6/moonbridge/callbacks"
PROBE="$ROOT/src/callbacks/pkg.generated.mbti"

to_native() {
  if command -v cygpath >/dev/null 2>&1; then
    printf '%s' "$(cygpath -m "$1")"
  else
    printf '%s' "$1"
  fi
}

if command -v python3 >/dev/null 2>&1; then
  PYTHON=python3
else
  PYTHON=python
fi

cd "$ROOT"

# An existing manifest is honoured, so a developer who ran `gen.sh all` gets
# the full corpus; a fresh checkout only has the standard library, which is all
# this script needs (`json`, `builtin` and `lexbuf` are all in it).
if [ ! -s "$ROOT/_corpus/manifest.txt" ]; then
  echo "== collecting interface dumps =="
  bash scripts/corpus.sh core >/dev/null
fi

echo
echo "== building the generator =="
moon build --target js

echo
echo "== interface dump for the callback probe =="
# `*.generated.mbti` is a build artifact and is not checked in, so the probe
# package's interface has to be written before the generator can read it.
moon info >/dev/null

echo
echo "== generating stubs, bindings and the guest =="
rm -rf "$OUT"
# The probe package is passed as a file rather than through the manifest: the
# manifest is the standard library dump, and this package is neither.
moon run --target js src/cli -- \
  --gen "$(to_native "$OUT")" \
  --bind "$BOUND" \
  --guest "$BOUND" \
  --guest-out "$(to_native "$ROOT/src/guest_gen")" \
  --list "$(to_native "$ROOT/_corpus/manifest.txt")" \
  "$(to_native "$PROBE")"

# The generator writes readable but unformatted code; `moon fmt` makes the
# checked-in copy the same file every run produces.
moon fmt >/dev/null 2>&1 || true
if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
  if git diff --quiet -- src/guest_gen; then
    echo "guest is in sync with the generator"
  else
    echo "note: src/guest_gen changed (a reviewable diff, not an error)"
  fi
fi

echo
echo "== building the guest =="
moon build --target wasm --release

echo
echo "== end to end =="
"$PYTHON" bench/e2e.py --package "$OUT" --wasm "$(to_native "$WASM")"

echo
echo "== mypy --strict on the generated modules =="
if "$PYTHON" -c "import mypy" 2>/dev/null; then
  # The stub and the module describe the same package, so one of the two has to
  # be left out of this run: mypy rejects a duplicate module. The stub is
  # checked by `gen.sh`, which is why the module is the one kept here.
  "$PYTHON" -m mypy --strict --no-incremental --python-version 3.13 \
    --exclude 'moonbitlang__core__(json|builtin|lexbuf)\.pyi$' \
    "$OUT/moonbridge"
else
  echo "skipped: mypy is not installed"
fi

echo
echo "== benchmark =="
"$PYTHON" bench/bench.py \
  --package "$OUT" \
  --wasm "$(to_native "$WASM")" \
  --calls "${BENCH_CALLS:-100000}"

echo
echo "== wheel =="
# Packs what the steps above produced, installs it into a throwaway venv, and
# runs the smoke test from outside the repository.
bash "$ROOT/scripts/wheel.sh"
