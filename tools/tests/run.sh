#!/usr/bin/env bash
set -uo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SIDECAR="$HERE/../bin/sidecar"
STUBS="$HERE/stubs"

if [ ! -x "$SIDECAR" ]; then
  printf 'run: %s is not executable\n' "$SIDECAR" >&2
  exit 1
fi

TMP="$(mktemp -d /tmp/sidecar-tests.XXXXXX)" || { printf 'run: cannot create a temp dir\n' >&2; exit 1; }
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAILED=0
CASES=0
CURRENT=""
OUT=""
RC=0

reset_case_env() {
  unset STUB_CONNECT_RC STUB_CONNECT_RC_SEQ STUB_CONNECT_OUT STUB_CONNECT_SLEEP
  unset STUB_CONNECT_LEAVES_DISPLAY STUB_CONNECT_SHOWS_DISPLAY_EARLY
  unset STUB_DISCONNECT_RC STUB_DISCONNECT_RC_SEQ STUB_DISCONNECT_OUT
  unset STUB_DISCONNECT_SLEEP STUB_DISCONNECT_LEAVES_DISPLAY
  unset STUB_DEVICES_OUT STUB_DEVICES_RC
  unset STUB_CONNECTED_RC STUB_CONNECTED_RC_SEQ STUB_DEVICE_NAME
  unset STUB_WAKE_RECONNECTS STUB_WAKE_SHOWS_DISPLAY
  unset STUB_SIDECAR_ALWAYS STUB_SIDECAR_FOR_CALLS STUB_SIDECAR_ID
  unset STUB_SIDECAR_MAIN STUB_SIDECAR_ACTIVE STUB_SIDECAR_MIRROR_OF
  unset STUB_SIDECAR_ASLEEP STUB_SIDECAR_RES STUB_ZOMBIE STUB_ZOMBIE_ID
  unset STUB_VDISP_ID STUB_VDISP_MAIN STUB_VDISP_RES STUB_VDISP_VENDOR STUB_VDISP_MODEL STUB_VDISP_RC
  unset STUB_BUILTIN STUB_BUILTIN_ID STUB_BUILTIN_RES
  unset STUB_ARRANGE_RC STUB_ARRANGE_OUT STUB_MIRROR_RC STUB_MIRROR_OUT
  unset STUB_SETMODE_RC STUB_SETMODE_OUT STUB_DISPMODE_RC STUB_DISPMODE_OUT
  unset STUB_CAFFEINATE_RC STUB_CAFFEINATE_SLEEP

  export CONNECT_ATTEMPTS=2
  export CONNECT_SETTLE=0
  export CONNECT_DISPLAY_WAIT=1
  export WAKE_SETTLE=1
  export RETRY_DELAY=0
  export TIMEOUT_RETRY_DELAY=0
  export CONNECT_TIMEOUT=1
  export DISCONNECT_TIMEOUT=1
  export VDISP_TIMEOUT=1
  export DOWN_TIMEOUT=1
  export RESTART_TIMEOUT=1
  export POLL_INTERVAL=0.01
}

new_case() {
  CASES=$((CASES + 1))
  CURRENT="$1"
  BIN="$TMP/bin-$CASES"
  STUB_DIR="$TMP/stub-$CASES"
  mkdir -p "$BIN" "$STUB_DIR" "$BIN/logs" "$BIN/state"
  cp "$STUBS"/* "$BIN"/
  chmod +x "$BIN"/* 2>/dev/null || true
  : >"$STUB_DIR/calls.log"
  TMP_BIN="$BIN"
  reset_case_env
}

export_stubs() {
  local name
  for name in $(compgen -v STUB_ 2>/dev/null || true); do
    export "$name"
  done
}

run_sidecar() {
  export_stubs
  OUT="$(SIDECAR_BIN="$BIN" STUB_DIR="$STUB_DIR" "$SIDECAR" "$@" 2>&1)"
  RC=$?
}

run_sidecar_with_bin() {
  local bin="$1"
  shift
  export_stubs
  OUT="$(SIDECAR_BIN="$bin" STUB_DIR="$STUB_DIR" "$SIDECAR" "$@" 2>&1)"
  RC=$?
}

pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail_case() {
  FAILED=$((FAILED + 1))
  printf 'FAIL %s\n' "$1"
  printf '     case:    %s\n' "$CURRENT"
  printf '     rc:      %s\n' "$RC"
  printf '     output:\n'
  printf '%s\n' "$OUT" | sed 's/^/     | /'
  if [ -s "$STUB_DIR/calls.log" ]; then
    printf '     calls:   %s\n' "$(tr '\n' ';' <"$STUB_DIR/calls.log")"
  fi
}

check() {
  local desc="$1"
  shift
  if "$@"; then pass "$desc"; else fail_case "$desc"; fi
}

connects() { grep -c '^connect ' "$STUB_DIR/calls.log" 2>/dev/null || true; }
disconnects() { grep -c '^disconnect ' "$STUB_DIR/calls.log" 2>/dev/null || true; }
probes() { grep -c '^connected ' "$STUB_DIR/calls.log" 2>/dev/null || true; }

expect_rc() { [ "$RC" -eq "$1" ]; }
expect_out() { printf '%s\n' "$OUT" | grep -qF -- "$1"; }
expect_no_out() { ! printf '%s\n' "$OUT" | grep -qF -- "$1"; }
expect_connects() { [ "$(connects)" -eq "$1" ]; }
expect_disconnects() { [ "$(disconnects)" -eq "$1" ]; }
expect_probes() { [ "$(probes)" -eq "$1" ]; }
expect_call() { grep -q "^$1" "$STUB_DIR/calls.log"; }
expect_log() { printf '%s\n' "$1" | grep -qF -- "$2"; }

CASE() { new_case "$1"; }

CASE "SIDECAR_BIN unset: behaviour is unchanged"
OUT="$(env -u SIDECAR_BIN "$SIDECAR" --help 2>&1)"; RC=$?
check "unset SIDECAR_BIN: --help exits 0" expect_rc 0
check "unset SIDECAR_BIN: usage is printed" expect_out "usage: sidecar <command>"

CASE "SIDECAR_BIN set to a non-directory fails loudly"
touch "$TMP/not-a-dir"
run_sidecar_with_bin "$TMP/not-a-dir" --help
check "malformed SIDECAR_BIN: non-zero exit" expect_rc 1
check "malformed SIDECAR_BIN: error names the variable" expect_out "ERROR: SIDECAR_BIN is set but not a usable directory: $TMP/not-a-dir"
check "malformed SIDECAR_BIN: no fallback usage" expect_no_out "usage: sidecar <command>"

CASE "SIDECAR_BIN set to a missing path fails loudly"
run_sidecar_with_bin "$TMP/does-not-exist" --help
check "missing SIDECAR_BIN directory: non-zero exit" expect_rc 1
check "missing SIDECAR_BIN directory: error names the variable" expect_out "ERROR: SIDECAR_BIN is set but not a usable directory: $TMP/does-not-exist"

CASE "SIDECAR_BIN set to a directory resolves every helper from it"
run_sidecar ensure
check "ensure: stub virtual display is up" expect_rc 0
check "ensure: reports the virtual display" expect_out "virtual display 0x5644 already up"

CASE "up with the stubs: one disconnect, one connect, arrange"
run_sidecar up
check "up: exits 0" expect_rc 0
check "up: one disconnect" expect_disconnects 1
check "up: one connect" expect_connects 1
check "up: arrange runs (no built-in display)" expect_call "arrange"
check "up: reports the connection" expect_out "Sidecar connected"

CASE "status: the live Sidecar wins over a zombie"
STUB_CONNECTED_RC=0
STUB_SIDECAR_ALWAYS=1
STUB_ZOMBIE=1
STUB_ZOMBIE_ID=30
STUB_SIDECAR_ID=22
STUB_SIDECAR_MIRROR_OF=17
run_sidecar status
check "status: exits 0 with a live display" expect_rc 0
check "status: reports the live id, not the zombie" expect_out "connected (id=22"
check "status: prints the mirror from dispid" expect_out "mirror:           sidecar 22 -> 17"

CASE "status: suspended display (asleep) is not a failure"
STUB_CONNECTED_RC=0
STUB_SIDECAR_ALWAYS=1
STUB_SIDECAR_MIRROR_OF=0
STUB_SIDECAR_ACTIVE=false
STUB_SIDECAR_ASLEEP=true
run_sidecar status
check "status: exits 0 (device connected)" expect_rc 0
check "status: names the suspended session" expect_out "suspended (display 22 asleep)"
check "status: no mirror" expect_out "mirror:           sidecar 22 -> none"

CASE "status: probe unknown with a live display is assumed connected"
STUB_CONNECTED_RC=3
STUB_SIDECAR_ALWAYS=1
STUB_SIDECAR_MIRROR_OF=17
run_sidecar status
check "status: exits 0 (assumed connected)" expect_rc 0
check "status: says the probe is unavailable" expect_out "probe unavailable"
check "status: uses the live display id" expect_out "display live (id=22"

CASE "status: orphaned display with no device is a failure"
STUB_CONNECTED_RC=1
STUB_SIDECAR_ALWAYS=1
STUB_SIDECAR_MIRROR_OF=0
STUB_SIDECAR_ACTIVE=false
STUB_SIDECAR_ASLEEP=false
run_sidecar status
check "status: exits 1" expect_rc 1
check "status: calls the display orphaned" expect_out "orphaned"

printf '\n%d cases, %d passed, %d failed\n' "$CASES" "$PASS" "$FAILED"
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
exit 0
