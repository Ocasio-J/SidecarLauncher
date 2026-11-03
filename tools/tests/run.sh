#!/usr/bin/env bash
set -uo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
TOOLS="$(cd -P "$HERE/.." && pwd)"
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
  CASE_DIR="$TMP/case-$CASES"
  BIN="$CASE_DIR/bin"
  STUB_DIR="$CASE_DIR/stub"
  mkdir -p "$BIN" "$STUB_DIR" "$CASE_DIR/logs" "$CASE_DIR/state"
  cp "$STUBS"/* "$BIN"/
  chmod +x "$BIN"/* 2>/dev/null || true
  : >"$STUB_DIR/calls.log"
  export STUB_DIR
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
  OUT="$(PATH="$BIN:$PATH" SIDECAR_BIN="$BIN" STUB_DIR="$STUB_DIR" "$SIDECAR" "$@" 2>&1)"
  RC=$?
}

run_sidecar_with_bin() {
  local bin="$1"
  shift
  export_stubs
  OUT="$(PATH="$bin:$PATH" SIDECAR_BIN="$bin" STUB_DIR="$STUB_DIR" "$SIDECAR" "$@" 2>&1)"
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
caffeinates() { grep -c '^caffeinate ' "$STUB_DIR/calls.log" 2>/dev/null || true; }

expect_rc() { [ "$RC" -eq "$1" ]; }
expect_out() { printf '%s\n' "$OUT" | grep -qF -- "$1"; }
expect_no_out() { ! printf '%s\n' "$OUT" | grep -qF -- "$1"; }
expect_connects() { [ "$(connects)" -eq "$1" ]; }
expect_disconnects() { [ "$(disconnects)" -eq "$1" ]; }
expect_caffeinates() { [ "$(caffeinates)" -eq "$1" ]; }
expect_call() { grep -q "^$1" "$STUB_DIR/calls.log"; }
expect_no_call() { ! grep -q "^$1" "$STUB_DIR/calls.log"; }
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

CASE "up: healthy session is a no-op but still arranges"
STUB_CONNECTED_RC=0
STUB_SIDECAR_ALWAYS=1
STUB_SIDECAR_MIRROR_OF=17
run_sidecar up
check "up healthy: exits 0" expect_rc 0
check "up healthy: no disconnect" expect_disconnects 0
check "up healthy: no connect" expect_connects 0
check "up healthy: says the session is healthy" expect_out "session healthy (id=22): no reconnect"
check "up healthy: still runs the layout step" expect_call "arrange"

CASE "up: probe unknown with a live display assumes healthy and warns"
STUB_CONNECTED_RC=3
STUB_SIDECAR_ALWAYS=1
run_sidecar up
check "up unknown: exits 0" expect_rc 0
check "up unknown: no connect" expect_connects 0
check "up unknown: points at --force" expect_out "use --force to reconnect"

CASE "up: a healthy session does not reapply state/resolution"
STUB_CONNECTED_RC=0
STUB_SIDECAR_ALWAYS=1
STUB_SIDECAR_RES=1024x768
printf '1321x918\n' > "$CASE_DIR/state/resolution"
run_sidecar up
check "up healthy with saved mode: exits 0" expect_rc 0
check "up healthy with saved mode: no connect" expect_connects 0
check "up healthy with saved mode: no setmode" expect_no_call "setmode"
check "up healthy with saved mode: no reconnect message" expect_no_out "pass 2"

CASE "up --force reconnects once even on a healthy session"
STUB_CONNECTED_RC=0
STUB_SIDECAR_ALWAYS=1
run_sidecar up --force
check "up --force: exits 0" expect_rc 0
check "up --force: one disconnect" expect_disconnects 1
check "up --force: one connect" expect_connects 1
check "up --force: not reported as healthy" expect_no_out "session healthy"

CASE "up: probe disconnected with a live display reconnects"
STUB_CONNECTED_RC=1
STUB_SIDECAR_FOR_CALLS=3
run_sidecar up
check "up disconnected: exits 0" expect_rc 0
check "up disconnected: reconnects" expect_connects 1

CASE "up: saved mode equals the negotiated mode: one connect, no pass 2"
STUB_CONNECTED_RC=1
STUB_SIDECAR_RES=1321x918
printf '1321x918\n' > "$CASE_DIR/state/resolution"
run_sidecar up
check "up saved mode equal: exits 0" expect_rc 0
check "up saved mode equal: one connect" expect_connects 1
check "up saved mode equal: no setmode" expect_no_call "setmode"

CASE "up: saved mode differs from the negotiated mode: pass 1 + pass 2"
STUB_CONNECTED_RC=1
STUB_SIDECAR_RES=1024x768
printf '1321x918\n' > "$CASE_DIR/state/resolution"
run_sidecar up
check "up saved mode differs: exits 0" expect_rc 0
check "up saved mode differs: two connects" expect_connects 2
check "up saved mode differs: setmode runs" expect_call "setmode"

CASE "A3: two flaps abort after two connects"
STUB_CONNECTED_RC=1
STUB_CONNECT_LEAVES_DISPLAY=0
run_sidecar up
check "flap twice: exits 1" expect_rc 1
check "flap twice: two connects" expect_connects 2
check "flap twice: names the stale display cause" expect_out "closed right after connecting twice"

CASE "A3: probe connected and no live display fails without a reconnect"
STUB_CONNECTED_RC=0
STUB_CONNECT_LEAVES_DISPLAY=0
run_sidecar up
check "connected but not live: exits 1" expect_rc 1
check "connected but not live: one connect" expect_connects 1
check "connected but not live: no live line message" expect_out "no live Sidecar display appeared"

CASE "A3: probe unknown and no live display fails without a reconnect"
STUB_CONNECTED_RC=3
STUB_CONNECT_LEAVES_DISPLAY=0
run_sidecar up
check "unknown but not live: exits 1" expect_rc 1
check "unknown but not live: one connect" expect_connects 1
check "unknown but not live: says the state is unknown" expect_out "session state is unknown"

CASE "A3: a zombie display is never a success"
STUB_CONNECTED_RC=0
STUB_CONNECT_LEAVES_DISPLAY=0
STUB_SIDECAR_MIRROR_OF=0
STUB_SIDECAR_ACTIVE=false
STUB_SIDECAR_FOR_CALLS=3
run_sidecar up
check "zombie present: exits 1" expect_rc 1
check "zombie present: one connect" expect_connects 1
check "zombie present: not connected" expect_no_out "Sidecar connected (id="

CASE "A4: every connect hangs: bounded by CONNECT_TIMEOUT"
STUB_CONNECTED_RC=1
STUB_CONNECT_SLEEP=5
CONNECT_TIMEOUT=1
CONNECT_ATTEMPTS=2
TIMEOUT_RETRY_DELAY=0
run_sidecar up
check "hung connect: exits 1" expect_rc 1
check "hung connect: one connect per attempt" expect_connects 2
check "hung connect: reported as a timeout" expect_out "timed out after 1s"

CASE "A4: exit 3 twice then 0 connects at attempt 3"
STUB_CONNECT_RC_SEQ="3 3 0"
CONNECT_ATTEMPTS=3
run_sidecar up
check "exit 3 then 0: exits 0" expect_rc 0
check "exit 3 then 0: three connects" expect_connects 3
check "exit 3 then 0: reports the connection" expect_out "Sidecar connected"

CASE "A4: a timeout with the probe connected waits instead of reconnecting"
STUB_CONNECTED_RC=0
STUB_CONNECT_SLEEP=5
STUB_CONNECT_SHOWS_DISPLAY_EARLY=1
CONNECT_TIMEOUT=1
run_sidecar up
check "timeout + connected: exits 0" expect_rc 0
check "timeout + connected: a single connect" expect_connects 1
check "timeout + connected: reports the connection" expect_out "Sidecar connected"

CASE "A4: a command that dies before the watchdog keeps its real exit code"
STUB_CONNECTED_RC=1
STUB_CONNECT_RC=7
CONNECT_TIMEOUT=2
run_sidecar up
check "quick failure: exits 1" expect_rc 1
check "quick failure: one connect" expect_connects 1
check "quick failure: not retryable" expect_out "not retryable"
check "quick failure: not reported as a timeout" expect_no_out "timed out"

CASE "A5: wake brings a suspended session back: no reconnect"
STUB_CONNECTED_RC=1
STUB_SIDECAR_ALWAYS=1
STUB_WAKE_RECONNECTS=1
run_sidecar up
check "wake healthy: exits 0" expect_rc 0
check "wake healthy: no connect" expect_connects 0
check "wake healthy: no disconnect" expect_disconnects 0
check "wake healthy: one caffeinate" expect_caffeinates 1
check "wake healthy: reports the session healthy" expect_out "session healthy"

CASE "A5: wake failure does not change the flow"
STUB_CONNECTED_RC=1
STUB_SIDECAR_ALWAYS=1
STUB_WAKE_RECONNECTS=1
STUB_CAFFEINATE_RC=1
run_sidecar up
check "wake failure: exits 0" expect_rc 0
check "wake failure: still no connect" expect_connects 0
check "wake failure: reports the session healthy" expect_out "session healthy"

CASE "A5: a display that survives the wake and the disconnect aborts with 0 connects"
STUB_CONNECTED_RC=1
STUB_SIDECAR_ALWAYS=1
run_sidecar up
check "surviving display: exits 1" expect_rc 1
check "surviving display: no connect (-501 avoided)" expect_connects 0
check "surviving display: one disconnect attempt" expect_disconnects 1
check "surviving display: names the abort" expect_out "wake and disconnect did not release the Sidecar display"
check "surviving display: points at sidecar down" expect_out "sidecar down"
check "surviving display: never SIGKILL/kickstart/bootout" expect_out "Never SIGKILL vdisp, kickstart -k or bootout"
check "surviving display: never reported healthy" expect_no_out "session healthy"

CASE "A5: --force skips the wake recovery but still caffeinates once"
STUB_CONNECTED_RC=1
STUB_SIDECAR_ALWAYS=1
run_sidecar up --force
check "force with residual: exits 0" expect_rc 0
check "force with residual: one caffeinate" expect_caffeinates 1
check "force with residual: one disconnect" expect_disconnects 1
check "force with residual: one connect" expect_connects 1

CASE "A5: no prior evidence goes straight to connect without caffeinate"
STUB_CONNECTED_RC=1
run_sidecar up
check "no evidence: exits 0" expect_rc 0
check "no evidence: one connect" expect_connects 1
check "no evidence: no caffeinate" expect_caffeinates 0

CASE "A5: a residual that clears on its own continues to connect"
STUB_CONNECTED_RC=1
STUB_SIDECAR_FOR_CALLS=3
run_sidecar up
check "residual cleared: exits 0" expect_rc 0
check "residual cleared: one caffeinate" expect_caffeinates 1
check "residual cleared: one connect" expect_connects 1

CASE "B1: one display-selection rule, staged as main.swift"
check "B1: src/disprule.swift exists" test -f "$TOOLS/src/disprule.swift"
check "B1: disprule declares onlineList" grep -q '^func onlineList' "$TOOLS/src/disprule.swift"
check "B1: disprule declares selectSidecar" grep -q '^func selectSidecar' "$TOOLS/src/disprule.swift"
check "B1: disprule declares selectVirtual" grep -q '^func selectVirtual' "$TOOLS/src/disprule.swift"
check "B1: disprule is declarations only" bash -c '! grep -qEv "^([[:space:]]*$|[[:space:]]+|(import|let|func|\}))" "$1"' _ "$TOOLS/src/disprule.swift"
check "B1: build.sh stages the helper as main.swift" grep -q 'cp "\$source" "\$stage/main.swift"' "$TOOLS/build.sh"
check "B1: build.sh compiles disprule with the staged main" grep -q 'swiftc -O -o "\$tmp" "\$stage/main.swift" "\$shared"' "$TOOLS/build.sh"
for shared_helper in mirror setmode dispmode arrange; do
  check "B1: $shared_helper is built with the shared rule" grep -q "^SHARED_HELPERS=.*[[:space:]]$shared_helper\|^SHARED_HELPERS=\"[^\"]*$shared_helper" "$TOOLS/build.sh"
done
if [ -x "$TOOLS/bin/dispid" ]; then
  OUT="$("$TOOLS/bin/dispid" 2>&1)"; RC=$?
  check "B1: the real dispid helper still runs" expect_rc 0
  check "B1: every dispid line ends with the resolution" bash -c 'printf "%s\n" "$1" | grep -qE "[0-9]+x[0-9]+$"' _ "$OUT"
fi

CASE "B2: mirror reports its failure instead of passing silently"
STUB_CONNECTED_RC=0
STUB_SIDECAR_ALWAYS=1
STUB_SIDECAR_MIRROR_OF=17
STUB_BUILTIN=1
STUB_MIRROR_RC=1
STUB_MIRROR_OUT="ERR: mirroring the Sidecar onto the built-in display failed (mirror=1001 commit=0)"
run_sidecar up
check "mirror failure: up still exits 0 (the session stays up)" expect_rc 0
check "mirror failure: one mirror attempt" expect_call "mirror"
check "mirror failure: warns about the mirror" expect_out "mirror failed"
check "mirror failure: no arrange when a built-in exists" expect_no_call "arrange"

CASE "B2: an already mirrored Sidecar is not an error"
STUB_CONNECTED_RC=0
STUB_SIDECAR_ALWAYS=1
STUB_SIDECAR_MIRROR_OF=1
STUB_BUILTIN=1
STUB_MIRROR_OUT="already mirrored: sidecar 22 -> builtin 1"
run_sidecar up
check "already mirrored: exits 0" expect_rc 0
check "already mirrored: mirror applied" expect_out "mirror applied onto the built-in display"

CASE "B2: mirror keeps the shared rule and the already-mirrored short-circuit"
check "B2: no headless vendor in the sources" bash -c '! grep -rq "0x756e6b6e" "$1"' _ "$TOOLS/src"
check "B2: mirror prints already mirrored" grep -q 'already mirrored: sidecar' "$TOOLS/src/mirror.swift"
check "B2: mirror exits 1 on a failed commit" grep -q 'r != .success || done != .success' "$TOOLS/src/mirror.swift"
check "B2: mirror uses selectSidecar" grep -q 'selectSidecar(' "$TOOLS/src/mirror.swift"

CASE "B3: arrange rc 3 is a warning, not a success message"
STUB_CONNECTED_RC=0
STUB_SIDECAR_ALWAYS=1
STUB_ARRANGE_RC=3
STUB_ARRANGE_OUT="result: arrangement applied but the check is not clean (main=false in_mirror_set=true mirror_of=17)"
run_sidecar up
check "arrange unverified: up exits 0" expect_rc 0
check "arrange unverified: warns" expect_out "WARN: arrange applied but not verified (see"
check "arrange unverified: no success message" expect_no_out "desktop arranged: virtual display is main"

CASE "B3: arrange rc 3 does not mask other failures"
STUB_CONNECTED_RC=0
STUB_SIDECAR_ALWAYS=1
STUB_ARRANGE_RC=1
run_sidecar up
check "arrange failed: up exit 0 (session up)" expect_rc 0
check "arrange failed: names the manual fix" expect_out "run bin/arrange by hand"
check "arrange failed: not the unverified warning" expect_no_out "not verified"

CASE "B3: arrange distinguishes a clean result from an unclean one"
check "B3: arrange exits 3 on an unclean check" grep -q 'exit(3)' "$TOOLS/src/arrange.swift"
check "B3: arrange still exits 0 when clean" grep -q 'exit(0)' "$TOOLS/src/arrange.swift"

CASE "B5: res explains a mirrored Sidecar"
STUB_CONNECTED_RC=0
STUB_SIDECAR_ALWAYS=1
STUB_SIDECAR_MIRROR_OF=17
run_sidecar res
check "res mirrored: exits 0" expect_rc 0
check "res mirrored: names the mirrored display" expect_out "note: Sidecar 22 mirrors display 17; the iPad shows display 17"
check "res mirrored: names the virtual size" expect_out "(VDISP_WIDTH/HEIGHT = 1321x918)"
check "res mirrored: says the mode is not what the iPad shows" expect_out "not this mode"

CASE "B5: res WxH still applies and saves with a mirrored Sidecar"
STUB_CONNECTED_RC=0
STUB_SIDECAR_ALWAYS=1
STUB_SIDECAR_MIRROR_OF=17
run_sidecar res 1165x809
check "res WxH mirrored: exits 0" expect_rc 0
check "res WxH mirrored: setmode ran" expect_call "setmode 1165x809"
check "res WxH mirrored: the mode is saved" test -f "$CASE_DIR/state/resolution"
check "res WxH mirrored: the note is printed" expect_out "mirrors display 17"
check "res WxH mirrored: reports the saved mode" expect_out "saved in"

CASE "B5: no note when the Sidecar does not mirror anything"
STUB_CONNECTED_RC=0
STUB_SIDECAR_ALWAYS=1
STUB_SIDECAR_ACTIVE=true
STUB_SIDECAR_MIRROR_OF=0
run_sidecar res
check "res unmirrored: exits 0" expect_rc 0
check "res unmirrored: no note" expect_no_out "note: Sidecar"

printf '\n%d cases, %d passed, %d failed\n' "$CASES" "$PASS" "$FAILED"
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
exit 0
