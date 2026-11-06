#!/usr/bin/env bash
# Proves the whole chain on a real package: `.mbti` -> stubs -> callable module
# -> wasm guest -> Python, then measures what the boundary costs.
#
#   1. build the guest as wasm and the generator as js
#   2. generate every stub, plus a callable module for json and builtin
#   3. drive the generated Python against the compiled guest
#   4. run the 100k-call benchmark, which exits non-zero on a leak
#
# Usage:
#   scripts/e2e.sh                # default 100k calls
#   BENCH_CALLS=20000 scripts/e2e.sh
#
# Requirements: moon, node, python + wasmtime (`pip install wasmtime`).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="${GEN_OUT:-$ROOT/_gen}"
WASM="$ROOT/_build/wasm/release/build/guest_json/guest_json.wasm"
BOUND="moonbitlang/core/json,moonbitlang/core/builtin"

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
# this script needs (`json` and `builtin` are both in it).
if [ ! -s "$ROOT/_corpus/manifest.txt" ]; then
  echo "== collecting interface dumps =="
  bash scripts/corpus.sh core >/dev/null
fi

echo
echo "== building the guest and the generator =="
moon build --target wasm --release
moon build --target js

echo
echo "== generating stubs and bindings =="
rm -rf "$OUT"
moon run --target js src/cli -- \
  --gen "$(to_native "$OUT")" \
  --bind "$BOUND" \
  --list "$(to_native "$ROOT/_corpus/manifest.txt")"

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
    --exclude 'moonbitlang__core__(json|builtin)\.pyi$' \
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
