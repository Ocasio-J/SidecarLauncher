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
LABEL="local.sidecar.vdisp"
TEMPLATE="$ROOT/daemon/$LABEL.plist.in"
AGENTS="$HOME/Library/LaunchAgents"
DEST="$AGENTS/$LABEL.plist"
UID_NUM="$(id -u)"
DOMAIN="gui/$UID_NUM"

usage() {
  cat <<EOF
usage: ./install.sh [--help]

Renders daemon/$LABEL.plist.in (replacing @@TOOLS@@ with $ROOT),
writes ~/Library/LaunchAgents/$LABEL.plist, validates it with plutil -lint,
then (re)loads it into $DOMAIN (bootout, errors ignored, then bootstrap).

Idempotent: run it again after moving the folder or rebuilding. No sudo.
EOF
}

die() { printf 'install: %s\n' "$*" >&2; exit 1; }

case "${1:-}" in
  "") ;;
  -h|--help) usage; exit 0 ;;
  *) printf 'install: unknown argument: %s\n' "$1" >&2; usage >&2; exit 1 ;;
esac

[ -f "$TEMPLATE" ] || die "missing $TEMPLATE"
[ -x "$ROOT/bin/vdisp" ] || die "bin/vdisp is missing, run ./build.sh first"
case "$ROOT" in
  *'#'*|*'&'*|*'\'*) die "path contains a character sed would mangle: $ROOT" ;;
esac

mkdir -p "$AGENTS"
staged="$AGENTS/.$LABEL.plist.$$"
trap 'rm -f "$staged"' EXIT

sed "s#@@TOOLS@@#$ROOT#g" "$TEMPLATE" >"$staged"
grep -qF "$ROOT" "$staged" || die "rendering produced no absolute path, check the template"
plutil -lint "$staged" >/dev/null || die "rendered plist is not valid"
chmod 644 "$staged"
mv -f "$staged" "$DEST"

printf 'template:   %s\n' "daemon/$LABEL.plist.in"
printf 'installed:  %s\n' "$DEST"
printf 'tools:      %s\n' "$ROOT"

oldpid="$(launchctl print "$DOMAIN/$LABEL" 2>/dev/null | sed -n 's/^[[:space:]]*pid = //p' | head -n 1)"
launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
if [ -n "$oldpid" ]; then
  for _ in $(seq 1 20); do
    kill -0 "$oldpid" 2>/dev/null || break
    sleep 0.5
  done
fi
if ! launchctl bootstrap "$DOMAIN" "$DEST"; then
  sleep 1
  launchctl bootstrap "$DOMAIN" "$DEST" || die "launchctl bootstrap failed for $DOMAIN (is a graphical session logged in?)"
fi

state="$(launchctl print "$DOMAIN/$LABEL" 2>/dev/null | sed -n 's/^[[:space:]]*state = //p' | head -n 1)"
pid="$(launchctl print "$DOMAIN/$LABEL" 2>/dev/null | sed -n 's/^[[:space:]]*pid = //p' | head -n 1)"

printf 'label:      %s\n' "$LABEL"
printf 'domain:     %s\n' "$DOMAIN"
printf 'state:      %s%s\n' "${state:-unknown}" "${pid:+ (pid $pid)}"
printf '\nlogs: %s/logs/vdisp.out.log and vdisp.err.log\n' "$ROOT"
