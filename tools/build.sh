#!/usr/bin/env bash
set -euo pipefail

SELF="${BASH_SOURCE[0]:-$0}"
while [ -L "$SELF" ]; do
  LINK_DIR="$(cd -P "$(dirname "$SELF")" && pwd)"
  SELF="$(readlink "$SELF")"
  case "$SELF" in
    /*) ;;
    *) SELF="$LINK_DIR/$SELF" ;;
  esac
done
ROOT="$(cd -P "$(dirname "$SELF")" && pwd)"
SRC="$ROOT/src"
BIN="$ROOT/bin"
UPSTREAM="$ROOT/../SidecarLauncher/main.swift"

HELPERS="vdisp mirror dispid dispmode setmode connected arrange"

usage() {
  cat <<EOF
usage: ./build.sh [--help]

Compiles src/<name>.swift into bin/<name> for: $HELPERS,
plus bin/SidecarLauncher from ../SidecarLauncher/main.swift.

Requires swiftc (Xcode command line tools). Fails on the first error, keeps going
through a complete rebuild otherwise: safe to re-run. No sudo.
EOF
}

die() { printf 'build: %s\n' "$*" >&2; exit 1; }

case "${1:-}" in
  "") ;;
  -h|--help) usage; exit 0 ;;
  *) printf 'build: unknown argument: %s\n' "$1" >&2; usage >&2; exit 1 ;;
esac

command -v swiftc >/dev/null 2>&1 || die "swiftc not found, install the Xcode command line tools"
[ -f "$UPSTREAM" ] || die "missing $UPSTREAM (upstream SidecarLauncher source)"
mkdir -p "$BIN"

trap 'rm -f "$BIN"/.*.building 2>/dev/null || true' EXIT

built=0
started=$SECONDS

compile() {
  local name="$1" source="$2" tmp="$BIN/.$1.building"
  [ -f "$source" ] || die "missing source: $source"
  printf '  %-15s <- %s\n' "$name" "${source#"$ROOT"/}"
  swiftc -O -o "$tmp" "$source"
  mv -f "$tmp" "$BIN/$name"
  built=$((built + 1))
}

printf 'building into %s\n' "$BIN"
for helper in $HELPERS; do
  compile "$helper" "$SRC/$helper.swift"
done
compile SidecarLauncher "$UPSTREAM"

for helper in $HELPERS SidecarLauncher; do
  [ -x "$BIN/$helper" ] || die "$BIN/$helper was not produced"
done

size="$(du -sk "$BIN" | awk '{print $1}')"
printf '\n%d binaries in %s (%s KB, %ds)\n' "$built" "$BIN" "$size" "$((SECONDS - started))"
