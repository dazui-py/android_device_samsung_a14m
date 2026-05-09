#!/usr/bin/env bash
set -euo pipefail

WITH_GIT=0
MAX_TEXT_BYTES="${MAX_TEXT_BYTES:-1048576}"
ROOT=""

for arg in "$@"; do
  case "$arg" in
    --with-git)
      WITH_GIT=1
      ;;
    --max-text-bytes=*)
      MAX_TEXT_BYTES="${arg#*=}"
      ;;
    *)
      ROOT="$arg"
      ;;
  esac
done

ROOT="${ROOT:-$(pwd)}"
ROOT="$(cd "$ROOT" && pwd)"
NAME="$(basename "$ROOT")"
STAMP="$(date +%Y%m%d-%H%M%S)"

OUT_BASE="$ROOT/_source_dump"
OUT_DIR="$OUT_BASE/${NAME}-${STAMP}"

mkdir -p "$OUT_DIR"

TEXT_DUMP="$OUT_DIR/${NAME}-source-dump.txt"
MANIFEST="$OUT_DIR/${NAME}-manifest.txt"
GIT_INFO="$OUT_DIR/${NAME}-git-info.txt"
PATCH_FILE="$OUT_DIR/${NAME}-uncommitted.patch"
ARCHIVE="$OUT_BASE/${NAME}-${STAMP}.tar.gz"

echo "[*] Root: $ROOT"
echo "[*] Output: $OUT_DIR"

# Git info
{
  echo "== repo =="
  echo "$ROOT"
  echo

  if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "== branch =="
    git -C "$ROOT" branch --show-current || true
    echo

    echo "== HEAD =="
    git -C "$ROOT" rev-parse HEAD || true
    echo

    echo "== remotes =="
    git -C "$ROOT" remote -v || true
    echo

    echo "== status =="
    git -C "$ROOT" status --short || true
    echo

    echo "== last commits =="
    git -C "$ROOT" log --oneline -n 30 || true
  else
    echo "Not a git repo."
  fi
} > "$GIT_INFO"

if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$ROOT" diff --binary > "$PATCH_FILE" || true
fi

# Manifest + readable text dump
{
  echo "SOURCE DUMP: $NAME"
  echo "DATE: $(date)"
  echo "ROOT: $ROOT"
  echo
  echo "Excluded from text scan:"
  echo ".git, _source_dump, out, build, .repo, node_modules"
  echo
} > "$TEXT_DUMP"

{
  echo "MANIFEST: $NAME"
  echo "DATE: $(date)"
  echo "ROOT: $ROOT"
  echo
  printf "%-12s  %-64s  %s\n" "SIZE" "SHA256" "PATH"
} > "$MANIFEST"

find "$ROOT" \
  \( \
    -path "$ROOT/.git" -o \
    -path "$ROOT/_source_dump" -o \
    -path "$ROOT/out" -o \
    -path "$ROOT/build" -o \
    -path "$ROOT/.repo" -o \
    -path "$ROOT/node_modules" \
  \) -prune -o -type f -print0 |
while IFS= read -r -d '' file; do
  rel="${file#$ROOT/}"
  size="$(wc -c < "$file" | tr -d ' ')"
  sha="$(sha256sum "$file" | awk '{print $1}')"

  printf "%-12s  %-64s  %s\n" "$size" "$sha" "$rel" >> "$MANIFEST"

  {
    echo
    echo "================================================================================"
    echo "FILE: $rel"
    echo "SIZE: $size bytes"
    echo "SHA256: $sha"
    echo "================================================================================"
  } >> "$TEXT_DUMP"

  if [ "$size" -eq 0 ]; then
    echo "[empty file]" >> "$TEXT_DUMP"
  elif [ "$size" -gt "$MAX_TEXT_BYTES" ]; then
    echo "[skipped: file larger than $MAX_TEXT_BYTES bytes]" >> "$TEXT_DUMP"
  elif grep -Iq . "$file"; then
    cat "$file" >> "$TEXT_DUMP"
    echo >> "$TEXT_DUMP"
  else
    echo "[skipped: binary file]" >> "$TEXT_DUMP"
  fi
done

# Optional full git history bundle
if [ "$WITH_GIT" -eq 1 ] && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$ROOT" bundle create "$OUT_DIR/${NAME}.bundle" --all
fi

# Source archive
TAR_EXCLUDES=(
  "--exclude=$NAME/_source_dump"
  "--exclude=$NAME/out"
  "--exclude=$NAME/build"
  "--exclude=$NAME/.repo"
  "--exclude=$NAME/node_modules"
)

if [ "$WITH_GIT" -eq 0 ]; then
  TAR_EXCLUDES+=("--exclude=$NAME/.git")
fi

tar "${TAR_EXCLUDES[@]}" -czf "$ARCHIVE" -C "$(dirname "$ROOT")" "$NAME"

echo
echo "[OK] Dump textual:"
echo "$TEXT_DUMP"
echo
echo "[OK] Manifest:"
echo "$MANIFEST"
echo
echo "[OK] Git info:"
echo "$GIT_INFO"
echo
echo "[OK] Patch:"
echo "$PATCH_FILE"
echo
echo "[OK] Archive:"
echo "$ARCHIVE"
