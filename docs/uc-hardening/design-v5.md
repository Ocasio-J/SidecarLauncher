# UC hardening design — v5

**v5 — resolves the third review.** Base: branch `uc-hardening` @ `7cbf7ee`. Item IDs from
`plan.md` (A1–A6, B1–B7, C1). v5 is self-contained: it reproduces the full design with the
third-review corrections folded in. Round 1 (7/7) and round 2 (3/3) resolutions are carried over
unchanged (see "Prior reviews"); this document only consolidates them.

## Resolution of the third review

**B1 — A5 has unreachable branches and a state without an exit — ACCEPTED.** Correct: A5 was
placed after the existing stale-display check (`bin/sidecar` 469–476), which already `fail`s on
`probe == disconnected && any_sidecar_line`, so A5's steps 3–5 were unreachable, and the two
post-wake evolutions (probe still `connected` + `any` present + `live` empty; and `connected` +
`any` gone) had no defined action. Fixed by rewriting A5 as one explicit flow (below): wake first,
every branch has a defined exit, `--force` skips it, and it is skipped when there is no prior
display evidence.

**B2 — A1 acceptance is not executable — ACCEPTED.** Correct on all three counts: the recorder's
`UC ACTIVE/IDLE` is UC's assertion (expected to release), `vdisp`'s hold is not in the recorder;
the `mv bin/connected` discriminator releases `vdisp`'s hold ≤30 s while the `displaysleep 10`
timer is already elapsed (headless SSH, no HID), reproducing 12:12:06; and "no VHID activity" is a
pre-check on a future event (a stray touch = inconclusive, not failed). Fixed: criterion rewritten
in measurable terms, discriminator guarded by `caffeinate -u -t 2` + ≤60 s window + restore check,
explicit contamination rule.

**C1 — A1 lines need ISO timestamps; read both logs; show age; `unknown` beyond ~120 s —
ACCEPTED.** A1's keep-awake lines now carry an ISO timestamp; C1 reads both `logs/vdisp.out.log`
(launchd) and `logs/vdisp.log` (`cmd_ensure`), takes the newest, shows its age, and prints
`unknown` when absent or older than ~120 s.

**`doctor` — incomplete state machine — ACCEPTED.** Re-added `probe == unknown`; every state is
now tagged `ok`/`info`/`FAIL`; the arrangement check is gated on `live` (no second misleading
FAIL); `disconnected + any` is fixed by "wake first, then lid cycle"; `CGDisplayIsAsleep` is
exposed as `asleep=` in `dispid` and used instead of assuming.

**`RESTART_TIMEOUT=30` — declared but absent from the body — ACCEPTED.** Written as a concrete
change in B6: `bin/sidecar` `RESTART_TIMEOUT=15` → `30`.

**A4 — acceptance arithmetic and sentinel — ACCEPTED.** Acceptance now uses the real formula
(`CONNECT_ATTEMPTS × CONNECT_TIMEOUT + (CONNECT_ATTEMPTS−1) × TIMEOUT_RETRY_DELAY`); the sentinel
is `( sleep; if kill -TERM "$pid" 2>/dev/null; then touch "$flag"; fi )` (touch only on a
successful kill).

**Low — ACCEPTED.** Removed the "a 30 s bound only makes failures faster" claim (contradicted by
the 124 branch); corrected the arithmetic; removed step 9 of the live protocol (redundant after the
discriminator).

**Order — ACCEPTED with modification.** A1+B6 move out of "last" to **right after A2–A5** (before
the B-items), rather than literally "after B4/A2", because the restart's own `up` must already be
the hardened one (A4 timeout, A3 flap-guard, A5 wake-recovery). One-line motivation in "Execution
order".

---

## Prior reviews (carried over unchanged from v3/v4)

- **Round 1 (7/7)**: A2 gate drops the mode comparison; A1 evidence-not-duration; A1 probe on a
  serial queue with a main-queue timeout; A3 extended poll + `unknown`-no-reconnect; A4
  `exec`/flag/`|| rc=$?`; live pass/fail split; phase-2 deploy sequence (restart-vdisp → install).
- **Round 2 (3/3 + annotations)**: staged-`main.swift` build mechanism; two named selectors
  (`live_sidecar_line` no-fallback, `any_sidecar_line` with fallback); three-state A2 gate; A1
  discriminator (`mv bin/connected`); A1 probe-timeout timer on main + `stopping` flag; A4 sentinel
  + env-overridable constants; B7 rewrites `usage_up` + "What it does"; `restart-vdisp` gate;
  open-lid geometry `mirror_of == builtin.id`; PD window `[PD-60s, PD+5s]`.
- **12:12 event (v4)**: A1 outcome test mandatory; A1 must not assume UC (A6); C1 shows both
  owners; A5 added; doctor "waiting for wake" vs "zombie". These are preserved and, where the third
  review corrects their *executability*, refined below.

---

## Goals

1. Stop causing Universal Control drops the tools do not need to cause (A2, A3, A4, A5).
2. Keep the displays awake for the life of a *live* Sidecar session — **never relying on UC's own
   assertion** (A1 + A6).
3. Recover from a display-sleep disconnect without a doomed `-501` connect (A5).
4. Fix the correctness gaps found in review (B1, B2, B4, B6).
5. Make the factors we cannot control visible (C1), and calibrate what "a drop" means to the user.

## Non-goals

- Changing UC defaults (`GlueIdleTimeout`, `AutomaticallyReconnect`): user decision (T2).
- Layout A/B (T5): deferred. Moving the recorder into `tools/`: deferred.
- Modifying `SidecarLauncher/main.swift`: unchanged; timeouts live in the wrapper.
- Touching `watch/`, `UC-DROPS.md`, `IMPLEMENTATION-PLAN.md`, or the `docs/uc-hardening/` base
  files (`analysis.md`, `plan.md`, `design-v3.md`, `design-v4.md`).
- No `up`/`down`, no `vdisp`/LaunchAgent restart, no `install.sh` during the offline phases.

---

## Execution order (v5)

| phase | items | deployment |
|---|---|---|
| 1 — offline | harness (`SIDECAR_BIN`), B4, A2, A3, A4, A5 | none (build + `bash -n` + harness) |
| 2 — live | A1 + B6 (one restart: build → restart-vdisp gate → install → up) | one restart |
| 3 — offline | B1, B2, B3, B5, C1 | none |
| 4 — docs | B7 | none |

**One-line motivation.** A1+B6 need exactly one vdisp restart wherever they land, and that restart
must run the hardened `up` (A4 timeout, A3 flap-guard, A5 wake-recovery), so they land right after
A2–A5 — before the B-items — to close the ~10-min idle-drop bleeding at the earliest safe point
without a second restart.

Notes: B4 precedes A2/A3/A5 (it provides `live_sidecar_line`/`any_sidecar_line` and the
`active=`/`mirror_of=`/`asleep=` fields). B3/B5 sit before C1 (last, info-only) so they can be cut.
C1 follows A1 because it reads A1's keep-awake logs. B1/B2 are Swift-helper correctness, offline
and independent of A1+B6, so they land after without a second restart.

---

## Item by item

### Harness + `SIDECAR_BIN` (offline)

**Change.** New `tools/tests/`: stubs for `SidecarLauncher`, `connected`, `dispid`, `vdisp`,
`arrange`, `mirror`, `setmode`, `dispmode`, **`caffeinate`** (for A5), driven by env vars (exit
code / output / sleep / "display appears after N calls"). `tools/tests/run.sh` runs `bin/sidecar`
with `BIN` pointing at the stubs. `bin/sidecar` gains one test-only override:

- `SIDECAR_BIN` unset → `BIN` derived from the script path **exactly as today**.
- `SIDECAR_BIN` set and a directory → `BIN="$SIDECAR_BIN"` (and `TOOLS`/`LOGS`/`RES_FILE` derive
  from it).
- `SIDECAR_BIN` set but not a directory → `fail` with
  `ERROR: SIDECAR_BIN is set but not a usable directory: …`, exit non-zero, no fallback.

**Acceptance [offline].** Unset → identical to today. Invalid → loud error. Temp dir → all helpers
resolve from it; A2–A5 cases pass.

**Regression risk.** Low.

### B4 — `dispid` exposes mirroring/sleep; two selectors; `doctor` state machine (offline)

**Change.** `dispid.swift`: add `active=<bool> mirror_of=<id> asleep=<bool>` **before** the
resolution (resolution stays last — `resolution()` reads `$NF`). `asleep` uses `CGDisplayIsAsleep`.
New line:
`id=… vendor=… model=… serial=… builtin=… main=… active=… mirror_of=… asleep=… WxH`.

`bin/sidecar` gains two distinct selectors:

- **`live_sidecar_line`** — the Sidecar line with `active=true` **or** `mirror_of=<id>` where
  `<id> != 0`; highest id; **no fallback** — empty when none exists. Used by A2, A3, A5, B5, the
  geometry test, and the arrangement check. This is the only "live" notion.
- **`any_sidecar_line`** — the first Sidecar line, with fallback (may be a zombie or a suspended
  display). Used **only** to describe in `status`/`doctor` and by A5's residual-display wait.

`virtual_line` (vendor `0x5644`, `main=true`, fallback first) is unchanged. Vendors anchored with
`([[:space:]]|$)`. `status`: `mirror: sidecar N -> M` from `dispid`; `mirror_state` only as
fallback.

**`doctor` Sidecar-state machine** (replaces the old mirror-based check; each state tagged):

| probe | live | any | asleep | verdict | message / fix |
|---|---|---|---|---|---|
| connected | present | — | — | **ok** | "Sidecar is connected and its display is live" |
| connected | empty | present | true | **info** | "Sidecar session suspended: waiting for display wake (display N asleep)" — `caffeinate -u -t 2`, or `sidecar up` (A5) |
| connected | empty | present | false | **info** | "device connected, display listed but not live and not asleep" — wait, or `sidecar up` |
| connected | empty | empty | — | **info** | "device connected, no display listed yet" — wait |
| disconnected | — | present | — | **FAIL** | "Sidecar display orphaned (no connected device)" — wake first (`caffeinate -u -t 2`, may re-enumerate); if still listed, open/close the lid |
| disconnected | — | empty | — | **ok** | "no Sidecar display and no connected device" |
| unknown | empty | present | — | **info** | "probe unavailable: cannot distinguish a suspended session from an orphan" — wake first, re-run doctor; if still listed, lid cycle |
| unknown | — | empty | — | **info** | "probe unavailable: no Sidecar display listed" |

The arrangement check (lid closed) is **gated on `live` present**: if `live` is present, OK iff
`virtual.main==true && live.mirror_of==virtual.id`, else FAIL; if `live` is empty, skip it (no
second misleading FAIL — the Sidecar-state row already reported the problem).

**Acceptance [offline]** build + `bash -n` + dispid fixtures through the harness, including:
"zombie present, no live line" (`live` empty, `any` non-empty) and "suspended session" (probe
`connected` + `any` present + `live` empty + `asleep=true` → suspended message, not zombie).
**[live]** `time sidecar doctor` < 1 s, no `system_profiler`, `consistent`.

**Regression risk.** Medium: `doctor`/`status` output changes. The added fields are append-only and
every existing grep anchors on `key=value` or `$NF`. Recorder ignores `status:`/`doctor:` lines.

### A2 — idempotent `up` (offline)

**Change.** In `cmd_up`, after `cmd_ensure`, a **three-state gate**:

- `live = live_sidecar_line()` (no fallback), `probe = sidecar_probe_state`.
- Geometry (lid closed): `virtual.main==true && live.mirror_of==virtual.id`; (lid open):
  `builtin_present && live.mirror_of==builtin.id`.
- Skip the reconnect iff `live` non-empty **and** `probe ∈ {connected, unknown}` and no `--force`:
  - `probe == connected` → `info "session healthy (id=…): no reconnect"`.
  - `probe == unknown` → `warn "probe unavailable: assuming the live display is the session; use
    --force to reconnect"`.
  - then run the layout step (`arrange`/`mirror`, idempotent); if geometry is not ok, the layout
    step fixes it **without a reconnect**; return 0.
- Otherwise → the A5 recovery path, then today's full path. The `state/resolution` comparison is
  **removed** from the gate; the only path that reapplies a saved mode is `up --force`. `main()`
  accepts `--force` for `up`; update `usage_up` and README (B7).

**Acceptance [offline, harness].** `connected` exit 0 + live line → rc 0, no `connect`/`disconnect`
line, arrange/mirror stub invoked. `connected` exit 3 + live line → rc 0, **0** connects, a WARN.
`connected` exit 3 + no live line → reconnect. `connected` exit 1 + live line → reconnect.
`--force` → exactly one disconnect + one connect.

**Regression risk.** Low; the fast path still runs the layout step.

### A3 — no reconnect storms (offline)

**Change.** In `connect_with_retries`, after `connect` exit 0 with no **live** line after
`CONNECT_SETTLE`:

- Poll up to `CONNECT_DISPLAY_WAIT=25` s for `live_sidecar_line()`.
- Live line appears → connected, success (success is **only** the live line, never a zombie).
- On expiry, branch on the probe:
  - `connected` → `fail` (session claims connected, no live display). No reconnect.
  - `disconnected` → count a *flap*; two flaps → `fail` (stale-display / iPad-held-elsewhere).
  - `unknown` → `fail "connect returned ok but the session state is unknown (probe unavailable)"`.
    No reconnect.
- Keep the existing classification for non-zero exits.

**Acceptance [offline, harness].** exit 0 + probe `disconnected` twice → abort, 2 connects.
exit 0 + probe `connected` + no live line after 25 s → fail, 1 connect. exit 0 + probe `unknown` →
fail, 1 connect, no reconnect. exit 0 + "zombie present, no live line" → fail (the zombie is not a
success).

**Regression risk.** Low.

### A4 — timeouts + exit-3 classification (offline)

**Change.** `bin/sidecar` only. `run_with_timeout SECONDS cmd…` (bash 3.2, no `timeout(1)`):

- Run `( exec "$@" ) > "$out" 2>&1 &`; `pid=$!`.
- Watchdog
  `( sleep "$secs"; if kill -TERM "$pid" 2>/dev/null; then touch "$flag"; fi ) &`; `watchdog=$!`.
  The sentinel is touched **only if the kill succeeds** (a process that already exited must not
  yield a spurious 124).
- `wait "$pid" || rc=$?` (errexit-safe); timeout is detected by the **sentinel file** `$flag`, never
  by the rc (a TERM-killed process returns 143).
- If `[ -f "$flag" ]` → `rc=124`; else keep `$rc`. Kill `$watchdog`, clean `$out`/`$flag` on both
  paths; never kill the process group.

Use for `connect` (`CONNECT_TIMEOUT=30`) and `disconnect` (`DISCONNECT_TIMEOUT=15`).
`classify_connect`: `rc 124` → **probe first** — if `connected`, do not reconnect (the daemon may
have completed the connect while the CLI was killed), poll for the live line and treat its
appearance as success, else `fail`; otherwise retry with `TIMEOUT_RETRY_DELAY=10`. `rc 3`
("not in the list of available devices") → `retry`. Keep the `connect "<NAME>" exit <rc>: …` format.

Timing constants are **env-overridable** (`CONNECT_TIMEOUT`, `DISCONNECT_TIMEOUT`,
`CONNECT_ATTEMPTS`, `CONNECT_SETTLE`, `CONNECT_DISPLAY_WAIT`, `WAKE_SETTLE`, `RETRY_DELAY`,
`TIMEOUT_RETRY_DELAY`, `VDISP_TIMEOUT`, `DOWN_TIMEOUT`, `RESTART_TIMEOUT`).

**Acceptance [offline, harness].** Stub sleeping 60 → `up` gives up after ≈
`CONNECT_ATTEMPTS × CONNECT_TIMEOUT + (CONNECT_ATTEMPTS−1) × TIMEOUT_RETRY_DELAY` (≈190 s with
defaults, ~seconds with env overrides), with clear messages. Stub exit 3 twice then 0 → connected at
attempt 3. Stub exit 124 with probe `connected` → no second connect; probe `disconnected` → retried
once. Stub that dies *before* the watchdog → the watchdog's kill fails → no sentinel → real rc
returned (not 124).

**Regression risk.** Low. The timeout only bounds a hung connect; the 124 branch probes before any
retry, so it does not add connects. The watchdog must not orphan and the temp files must be cleaned.

### A5 — recover from a display-sleep disconnect without `-501` (offline)

**Why.** 13:17:45: after `Display Sleep: Disconnecting`, Sidecar kept a session waiting to reconnect
on wake and display 23 stayed listed. `up` disconnected it (accepted, no `-102`) and its connect
failed `-501` (display 23 still present). The old stale-display check did not fire because the probe
did not say `disconnected`.

**Change.** In `cmd_up`, replacing the standalone stale-display abort (it is folded in), after
`cmd_ensure`:

1. Compute `probe`, `live = live_sidecar_line()`, `any = any_sidecar_line()`.
2. **A2 gate** (unchanged): if `live` non-empty and `probe ∈ {connected, unknown}` and no `--force`
   → layout step, return 0.
3. **A5 recovery** — run **only if** no `--force` **and** (`any` non-empty **or**
   `probe == connected`); otherwise skip to step 4.
   a. `caffeinate -u -t 2`.
   b. Poll ≤ `WAKE_SETTLE=10` s, re-reading `live`/`any`/`probe` each tick:
      - `live` non-empty → the suspended session self-reconnected → layout step, return 0.
      - `any` empty and `probe == disconnected` (or `unknown`) → residual cleared and no session
        owns it → stop polling, continue to step 4.
      - `any` empty and `probe == connected` → session present, no display yet → stop polling,
        continue to step 4.
   c. If `any` is still present after the poll (wake did not clear it):
      - `disconnect_quiet` (accepted without `-102` for a suspended session, per the 13:17 event).
      - `sleep 1`; poll ≤ `WAKE_SETTLE` for `any` to clear.
      - `any` cleared → continue to step 4.
      - `any` still present → `fail` stale-display message, return 1.
4. **Connect** (reached with `live` empty and `any` cleared, or with no prior evidence):
   `disconnect_quiet` (skip if already done in 3c) → `connect_with_retries` (A3/A4) → resolution →
   layout.

Every branch has a defined exit: self-reconnect → return 0; cleared → connect; persist → abort.
`--force` skips step 3 (and its abort) entirely. No prior evidence (`any` empty **and**
`probe != connected`) skips step 3 (no pointless `caffeinate` + waits when the iPad is simply away).

**Acceptance [offline, harness].** `dispid` stub listing a Sidecar for the first N calls +
`connected` stub returning `connected` after the wake → no connect, "session healthy". `connected`
stub staying `disconnected` + `dispid` stub that keeps listing the Sidecar → abort with the
stale-display message, **0** connects (no `-501`). `--force` with the same stubs → one disconnect +
one connect (A5 skipped). `any` empty + probe `disconnected` → straight to connect, no `caffeinate`
call.

**Regression risk.** Low; the only new external call is `caffeinate -u -t 2`, idempotent and safe
without sudo, and it runs only on the non-healthy, non-`--force` path with prior display evidence.

### A1 — keep displays awake for a *live* session, independent of UC (live, with B6)

**Change.** `vdisp.swift` + `daemon/local.sidecar.vdisp.plist.in`.

Hold `kIOPMAssertionTypePreventUserIdleDisplaySleep` (`"local.sidecar.vdisp: Sidecar session"`)
while a live session is evidenced. **Evidence, not duration, never assuming UC (A6):**

- Hold iff `VDISP_KEEP_AWAKE != "0"` (default on) **and** `connected` exits 0 **and** an online
  display with vendor `0x6161706c` exists (`CGGetOnlineDisplayList`).
- Release iff any term fails: env off, `connected` exits 1 (disconnected), probe unavailable (spawn
  fails / missing binary / **`probe=timeout`** / exit 3 — all **fail-safe: release**), or no online
  Sidecar display.
- Optional backstop `KEEP_AWAKE_MAX_HOLD` (default `0` = off; e.g. `86400` if a hard ceiling is
  wanted). Clock resets on an observed release *or* a change of the online Sidecar display id.

**Why it cannot rely on UC (A6).** The 12:12 event shows UC releases its own
`PreventUserIdleDisplaySleep` ~10 min after the last A051E41E input session ends (12:11:34 after
12:01:44), and the display sleeps 32 s later — `GlueIdleTimeout=3600` does **not** guarantee a hold.
`vdisp`'s assertion is the only one owned by the session itself; C1 shows both owners.

**Concurrency.** A dedicated serial `probeQueue` runs the probe via `Process.waitUntilExit()`. The
~5 s timeout is a `DispatchSourceTimer` on the **main** queue (calls `process.terminate()`, sets a
`probeTimedOut` flag), **not** on `probeQueue` (blocked in the wait). Timeout is logged
`probe=timeout`, distinct from `probe=3`. The `CGDisplayRegisterReconfigurationCallback` callback
only does `probeQueue.async { evaluate() }`. A 30 s `DispatchSourceTimer` also enqueues `evaluate()`.
The assertion create/release is applied on the main queue. A `stopping` flag is set by B6's signal
handler before release; the `evaluate()` completion checks it and skips the assertion-create while
set.

**Logging.** Each transition to stdout **with an ISO timestamp prefix** (same format as
`sidecar.log`): `TS keep-awake on (connected=N)`, `TS keep-awake off (probe=<rc|timeout> | no
sidecar display | env)`, `TS keep-awake off (backstop)`. Written to `logs/vdisp.out.log` (launchd)
or `logs/vdisp.log` (`cmd_ensure`); C1 reads **both**.

**Template.** Add `<key>VDISP_KEEP_AWAKE</key><string>1</string>` under `EnvironmentVariables`.

**Acceptance [live].**

- **Mechanism.** Session up: `pmset -g assertions` lists `PreventUserIdleDisplaySleep` owned by
  `vdisp` (by name), alongside UC — both visible in `status` (C1/A6). `VDISP_KEEP_AWAKE=0`: never
  held.
- **Discriminator (guarded).** `caffeinate -u -t 2` → `mv bin/connected bin/connected.off` → the
  assertion disappears ≤30 s (via `pmset`) → `mv bin/connected back` → the assertion returns ≤30 s.
  **Release window ≤60 s; verify the restore before proceeding.** The `caffeinate` resets the
  display-sleep idle timer so the ≤60 s release cannot trigger a display sleep.
- **Outcome (mandatory).** At the end of `[T0, T0+13 min]` (contamination rule below):
  - the recorder shows **no** `Display is turned off`, **no** `Display Sleep: Disconnecting`, and
    **no** VHID cancellation of `A051E41E`; **and**
  - `pmset -g assertions` still lists the assertion named `local.sidecar.vdisp: Sidecar session`.
  UC's own assertion may be released during the window (it follows the input session): that is
  **expected**, not a failure.
  - **Contamination rule:** any A051E41E VHID activity in `[T0, T0+13 min]` makes the run
    **inconclusive** (not failed); repeat it.

**Regression risk.** `vdisp` is the display owner: a crash drops the display and the session dies at
the next lid close. Mitigated: the probe path is isolated on its own queue with a main-queue
timeout, every failure releases (never throws), and the backstop is off by default.

### B6 — `vdisp` handles SIGTERM explicitly; install sequence (live, with A1)

**Change.** `vdisp.swift`: `signal(SIGTERM, SIG_IGN)` and `signal(SIGINT, SIG_IGN)`, then
`DispatchSource.makeSignalSource` for both. On fire: (1) set `stopping`; (2) release the A1
assertion synchronously; (3) drop the display reference (`var display: NSObject?` → `nil`);
(4) wait 0.5 s on the main queue; (5) `exit(0)`. Template: add
`<key>ThrottleInterval</key><integer>10</integer>`.

`install.sh`: after `bootout`, poll ≤10 s for the old pid to disappear before `bootstrap`; if
`bootstrap` fails, wait and retry once.

`bin/sidecar`: **`RESTART_TIMEOUT=15` → `RESTART_TIMEOUT=30`** (the restart-vdisp gate waits longer
for the new display to appear after SIGTERM).

After B6, `bootout` (SIGTERM) is safe once the new binary is running; `SIGKILL` / `kickstart -k`
still orphan.

**Deployment sequence (mandatory, live):** `./build.sh` → `sidecar restart-vdisp` (SIGTERM old;
KeepAlive restarts the **new** binary) **as a hard gate** → `./install.sh` (bootout hits the new
handler; poll pid; bootstrap; retry once).

**Acceptance [live].** `sidecar restart-vdisp` leaves exactly one `0x5644` display and
`vdisp.out.log` shows the shutdown line — this is a **gate**: if it does not hold, stop.

**Regression risk.** Medium: a handler that fails to release before `exit` re-orphans. Verified by
"exactly one `0x5644`". Order after A1 (it releases A1's assertion).

### B1 — shared display-selection rule (offline build, live assert)

**Change.** New `src/disprule.swift`, **declarations only**: `onlineList()`,
`selectSidecar(_:)`, `selectVirtual(_:)`.

- **Sidecar** (`0x6161706c`): online, prefer `CGDisplayIsActive != 0 ||
  CGDisplayMirrorsDisplay != 0`; among those, highest id.
- **Virtual** (`0x5644`): online, prefer `CGDisplayIsMain != 0`, then active, then largest.

`arrange.swift` replaces "first Sidecar" (~:35) and "largest virtual" (~:41); `setmode.swift`,
`dispmode.swift`, `mirror.swift` switch `CGGetActiveDisplayList` → `CGGetOnlineDisplayList`.

**Build mechanism (exact).** Multi-file `swiftc` only permits top-level code in a file named
`main.swift`, so `build.sh` stages the helper source under that name:

```bash
compile_shared() {
  local name="$1" source="$2" tmp="$BIN/.$1.building" stage="$BIN/.stage-$1"
  mkdir -p "$stage"
  cp "$source" "$stage/main.swift"          # top-level code is only legal in main.swift
  swiftc -O -o "$tmp" "$stage/main.swift" "$SRC/disprule.swift"
  mv -f "$tmp" "$BIN/$name"
}
```

Applied to `arrange`, `setmode`, `dispmode`, `mirror`. `vdisp`, `connected`, `dispid` compile
single-file (unchanged). Stage dirs removed on EXIT (extend the trap).

**Acceptance [offline]** build + `bash -n` (the staged compile is the proof). **[live]**
`bin/dispmode` lists the Sidecar while mirrored; `bin/setmode 1321x918` finds it; `sidecar res`
shows modes.

**Regression risk.** Low for the read helpers. `mirror` runs only with a built-in; its idempotence
lands in B2, so keep B1→B2 order.

### B2 — `mirror` reports failure and is idempotent (offline-only this cycle)

**Change.** `mirror.swift`: use the B1 rule; drop `0x756e6b6e` from `isSidecar`. If
`CGDisplayMirrorsDisplay(sidecar) == builtin`, print `already mirrored: sidecar N -> builtin M`,
exit 0. Exit 1 when `CGConfigureDisplayMirrorOfDisplay` or `CGCompleteDisplayConfiguration` is not
`.success`.

**Acceptance [offline]** build + logic review. Live exercise deferred to a lid-open session
(closed-lid `up` never calls `mirror`).

**Regression risk.** Low.

### B3 — `arrange` exit 3 on unclean result (offline) — cuttable

**Change.** `arrange.swift` phase 4 (~:128): exit **3** for "applied but not clean". In `cmd_up`:
rc 3 → `warn "arrange applied but not verified (see logs/arrange.log)"`; other non-zero → today's
warning; 0 → today's info.

**Acceptance [offline]** harness stub returns 3 → WARN (not INFO).

**Regression risk.** None. Cut candidate.

### B5 — `res` explains a mirrored Sidecar (offline) — cuttable

**Change.** `res_show` and `cmd_res`: if `live_sidecar_line` has `mirror_of≠0`, print
`note: Sidecar mirrors display N; the iPad shows display N (VDISP_WIDTH/HEIGHT), not this mode.`
Still allow `res WxH`.

**Acceptance [offline]** fixture with `mirror_of≠0` → note printed.

**Regression risk.** None. Cut candidate.

### C1 — `status`/`doctor` show UC defaults, **both** owners, and A1 probe state (offline, info-only)

**Change.** Read-only, `info` only, no FAIL rule this cycle. **A6 applies**: show *both* owners of
`PreventUserIdleDisplaySleep` (`vdisp` and `UniversalControl`).

- `status`: `uc defaults: GlueIdleTimeout=… AutomaticallyReconnect=…` from
  `defaults read com.apple.universalcontrol <key> 2>/dev/null` (else `unset`); `display awake:
  <owner list>` = **all** owners from `pmset -g assertions` (typically `vdisp, UniversalControl`);
  and `keep-awake: <line> (<Ns> ago)` = the newest keep-awake line, read from **both**
  `logs/vdisp.out.log` and `logs/vdisp.log`, showing its age; print `unknown` if absent or older
  than ~120 s. This is the only channel that surfaces A1's `probe=timeout`/`probe=3`/`probe=ok`.
- `doctor`: an `info` line with the UC defaults and the display-awake owner list.

**Parsing rule (hard).** `pmset -g assertions` output is not contractual: if the expected
section/keys/owner names are absent or `pmset` fails, print `unknown` / `none`. Never synthesize;
never infer an owner from a pid not present in the section. The deferred FAIL rule is out of scope.

**Acceptance [offline]** harness feeds a recorded `pmset -g assertions` fixture + stubbed `defaults`
+ a two-log keep-awake fixture → correct `unknown`/value output; multi-owner fixture shows
`vdisp, UniversalControl`; a keep-awake line older than 120 s → `unknown`. **[live]** phase 2:
`status` shows the real owner list and keep-awake/probe line with a fresh age.

**Regression risk.** Low (read-only). The `unknown`-never-invent rule is the only hard requirement.

### B7 — README + `usage_up` (offline, last)

- Rewrite the "SIGTERM releases / SIGKILL does not" rule to describe the B6 handler; `bootout` is
  safe once B6 is running; `SIGKILL` / `kickstart -k` still orphan.
- Remove/qualify the "~1 min vs ~4 min" figure in **three places**: `README.md` ~68–69, `README.md`
  ~366, `bin/sidecar` `usage_up` ~269–271. Link `UC-DROPS.md`.
- Rewrite `usage_up` steps 3–7 and the README "What it does" line (unconditional
  disconnect+connect+setmode that A2 no longer runs); state `up` is idempotent, `--force` is the
  only path that reapplies a saved mode, and `up` wakes displays and waits for a suspended session
  before connecting (A5).
- Document `VDISP_KEEP_AWAKE` (+ `KEEP_AWAKE_MAX_HOLD`), `up --force`, the timeouts, the new
  `dispid` fields (`active`/`mirror_of`/`asleep`), `SIDECAR_BIN`, the perceived-drop marker, and the
  "Sidecar waiting for display wake" `doctor` state.
- Known limits: "every switch of the iPad between Macs costs one UC drop per transition (OS
  behaviour)".

---

## Operational definition of "perceived drop", and the live-verification protocol

**Definition.** A **perceived drop (PD)** is the moment the user, actively typing or clicking from
the work Mac (`IDS A051E41E`), notices input stop on the personal Mac. It is the only ground truth.
`Peer appears missing` (UC↔iPad link) and `VHID … Canceling Service` (A051E41E input link) are
proxies that the data show can fire *without* a perceived drop (the reverse is not established).

**Who annotates.** The user, at the moment of noticing. **Format.** One ISO-timestamped line to
`tools/logs/perceived.log` (git-ignored):
`<ISO8601 ts> perceived-drop <note>` via
`printf '%s perceived-drop %s\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" "$note" >> tools/logs/perceived.log`.

**Comparison.** For each PD, read the recorder window `[PD-60s, PD+5s]`; if no trigger falls inside,
mark it **unexplained**.

**Scheduled resets.** In order:

1. `./build.sh` → no impact.
2. `sidecar restart-vdisp` — **gate** (exactly one `0x5644`, new pid, shutdown line) → 1 reset.
3. `./install.sh` → 1 reset.
4. `sidecar up` → 1 reset.
5. `sidecar up` again → **0** resets (A2 proof; any recorder event fails).
6. A1 discriminator (guarded: `caffeinate -u -t 2`, ≤60 s, restore+verify) → 0 resets.
7. `sidecar status` / `doctor` → 0 resets (both owners, suspended/orphan states, `asleep`).
8. A1 outcome idle test `[T0, T0+13 min]` → 0 resets (mandatory; contamination rule).

**Pass/fail (falsifiable).**

- **Objective pass**: recorder shows no iPad-link reset outside the scheduled step windows (2, 3,
  4); step 5 produces zero events; step 2's gate holds; step 8 passes.
- **PD overlay**: a PD outside the scheduled windows = **failure**; a PD inside a scheduled window =
  evidence about the two-link model (recorded, not a failure); a PD with no trigger in
  `[PD-60s, PD+5s]` = unexplained, reported.
- A051E41E `Canceling Service` is corroboration only, never a pass/fail criterion **except** as the
  step-8 outcome signal.
- **A1**: proof is **mechanism** (named assertion + guarded discriminator) **and outcome** (step 8),
  both mandatory.
- **A5**: offline-only this cycle (a display-sleep event is not reproduced on demand); if step 8
  unexpectedly fails, A5 is what recovers, and that recovery is recorded as the live demonstration.

---

## Cuts, and why

- **B5 first**: cosmetic `res` note; nothing depends on it.
- **B3 second**: `up` already warns when `arrange` fails; B3 only refines severity.
- **Never cut**: B1, B4 (real bugs), A1/A2/A3/A4/A5 (UC-drop causes and recovery), B6 (SIGTERM
  claim).

## Extension points

- `KEEP_AWAKE_MAX_HOLD` and `VDISP_KEEP_AWAKE` (A1), `SIDECAR_BIN` (harness), the timing constants
  (A4/A5).
- `connected.swift` stays the single source of truth for "live session".
- `src/disprule.swift` is the single source of the display-selection rule.

---

## Commits (one per item, English, `Verify:` paragraph)

1. `test: add offline harness and SIDECAR_BIN override`
2. `feat(dispid): expose active/mirror_of/asleep; add live/any sidecar selectors` (B4)
3. `feat(up): make up idempotent with --force and probe-unknown policy` (A2)
4. `fix(up): stop reconnect storms after a connect-then-close` (A3)
5. `fix(up): bound connect/disconnect with timeouts, retry exit 3` (A4)
6. `fix(up): wake displays and recover from a sleep-disconnect without -501` (A5)
7. `feat(vdisp): keep displays awake for a live session, independent of UC` (A1 + A6)
8. `fix(vdisp): handle SIGTERM explicitly; throttle KeepAlive; install waits; RESTART_TIMEOUT 30` (B6)
9. `refactor: shared display-selection rule via staged main.swift` (B1)
10. `fix(mirror): report failure and short-circuit when already mirrored` (B2)
11. `fix(arrange): exit 3 when the arrangement is not verified` (B3, cuttable)
12. `feat(res): explain a mirrored Sidecar` (B5, cuttable)
13. `feat(status,doctor): UC defaults, both owners, probe state, suspended/orphan states` (C1 + A6)
14. `docs: correct SIGTERM/bootout rule, UC figures, and the up flow` (B7)

Deployment note: commits 7 and 8 are deployed together in the sequence
`build.sh → restart-vdisp (gate) → install.sh`; every other commit is build/`bash -n`/harness-
verified without touching the session. A6 is a binding note folded into commits 7 and 13.
