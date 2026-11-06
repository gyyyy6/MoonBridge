#!/usr/bin/env bash
# Generates Python stubs for the whole corpus and type-checks them.
#
#   1. collect the same interface dumps S1 parses (scripts/corpus.sh)
#   2. emit one .pyi per package plus the runtime module
#   3. run `mypy --strict` over the generated package
#
# The last step is the S2 acceptance criterion: 0 errors, no ignores.
#
# Usage:
#   scripts/gen.sh              # both corpora
#   scripts/gen.sh core         # standard library only (no network)
#   scripts/gen.sh deps         # third-party only
#
# Requirements: moon, node, python + mypy (`pip install mypy`).
# Output directory: $GEN_OUT, default _gen/
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="${GEN_OUT:-$ROOT/_gen}"
LIST="$ROOT/_corpus/manifest.txt"

# Map MSYS/Cygwin paths to something node can open.
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

echo "== collecting interface dumps =="
bash scripts/corpus.sh "${1:-all}" >/dev/null

echo
echo "== generating stubs =="
rm -rf "$OUT"
moon run --target js src/cli -- --gen "$OUT" --list "$(to_native "$LIST")"

echo
echo "== mypy --strict =="
"$PYTHON" -m mypy --strict --no-incremental --python-version 3.13 "$OUT/moonbridge"
