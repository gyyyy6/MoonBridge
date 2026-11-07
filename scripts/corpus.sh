#!/usr/bin/env bash
# Collects real .mbti interface files and runs the parser over all of them.
#
# Two corpora:
#   core   the interface dumps shipped with the MoonBit standard library
#   deps   every interface dump published by the modules in corpus/packages.txt
#          (plus their transitive dependencies)
#
# Usage:
#   scripts/corpus.sh              # both corpora
#   scripts/corpus.sh core         # standard library only (no network)
#   scripts/corpus.sh deps         # third-party only (needs the registry)
#
# Exit code is non-zero when any file fails to parse, so this can gate CI.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK="${CORPUS_WORKDIR:-$ROOT/_corpus}"
LIST="$WORK/manifest.txt"

# Map MSYS/Cygwin paths to something node can open.
to_native() {
  if command -v cygpath >/dev/null 2>&1; then
    # `$(...)` strips the trailing newline cygpath emits, so callers can add
    # their own line break without producing blank manifest entries.
    printf '%s' "$(cygpath -w "$1" | sed 's|\\|/|g')"
  else
    printf '%s' "$1"
  fi
}

core_dir() {
  if [ -n "${MOON_CORE:-}" ]; then
    printf '%s' "$MOON_CORE"
    return
  fi
  local moon_bin
  moon_bin=$(command -v moon)
  printf '%s' "$(cd "$(dirname "$moon_bin")/.." && pwd)/lib/core"
}

collect_core() {
  local core out
  core=$(core_dir)
  out="$1"
  if [ ! -d "$core" ]; then
    echo "core corpus: no standard library at $core" >&2
    return
  fi
  find "$core" -name '*.mbti' -not -path '*/_build/*' -print0 \
    | while IFS= read -r -d '' f; do to_native "$f"; echo; done >> "$out"
}

# Builds a throwaway module that depends on every pinned package, so `moon
# check` downloads them into .mooncakes together with their .mbti dumps.
collect_deps() {
  local out scratch
  out="$1"
  scratch="$WORK/deps"
  rm -rf "$scratch"
  mkdir -p "$scratch/src/dummy"
  cat > "$scratch/moon.mod" <<'MOD'
name = "moonbridge/corpus"
version = "0.0.0"
source = "src"
MOD
  printf 'pkgtype(kind: "library")\n' > "$scratch/src/dummy/moon.pkg"
  : > "$scratch/src/dummy/lib.mbt"

  local imports=""
  while IFS= read -r line; do
    case "$line" in
      ''|'#'*) continue ;;
    esac
    imports="$imports  \"$line\",
"
  done < "$ROOT/corpus/packages.txt"
  {
    echo
    echo "import {"
    printf '%s' "$imports"
    echo "}"
  } >> "$scratch/moon.mod"

  echo "deps corpus: resolving $(grep -cvE '^$|^#' "$ROOT/corpus/packages.txt") modules"
  # Keep stderr visible: when the registry is unreachable or a pinned module no
  # longer resolves, the real reason has to show up in the CI log.
  ( cd "$scratch" && moon check >/dev/null ) || {
    echo "deps corpus: moon check failed; the downloads may be incomplete" >&2
  }
  if [ -d "$scratch/.mooncakes" ]; then
    find "$scratch/.mooncakes" -name '*.mbti' -print0 2>/dev/null \
      | while IFS= read -r -d '' f; do to_native "$f"; echo; done >> "$out"
  else
    echo "deps corpus: no packages were downloaded; only the core corpus is available" >&2
  fi
}

mkdir -p "$WORK"
: > "$LIST"

targets="${1:-all}"
case "$targets" in
  all)  collect_core "$LIST"; collect_deps "$LIST" ;;
  core) collect_core "$LIST" ;;
  deps) collect_deps "$LIST" ;;
  *)    echo "usage: $0 [all|core|deps]" >&2; exit 2 ;;
esac

count=$(wc -l < "$LIST" | tr -d ' ')
if [ "$count" -eq 0 ]; then
  echo "corpus: no .mbti files found" >&2
  exit 1
fi
echo "corpus: $count interface files"
echo

cd "$ROOT"
# --graph also builds the type graph for each file, so a parse that succeeds
# but yields nonsense is caught here rather than in the generator.
moon run --target js src/cli -- --quiet --graph --list "$(to_native "$LIST")"
