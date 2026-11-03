# UC hardening design — v4

**v4 = v3 + delta from the 12:12 → 13:19 event.** Base: branch `uc-hardening` @ `7cbf7ee`.
Item IDs from `plan.md` (A1–A6, B1–B7, C1). v4 is self-contained: it reproduces the v3 design
in full with the event-driven changes folded in. The review resolutions of rounds 1 and 2 are
unchanged and carried over (see "Prior reviews").

## Changes since v3 (delta)

1. **A1 outcome test is now mandatory, not "mechanism-only".** The 12:12 event makes the idle
   test reproducible and discriminating: UC released its assertion ~10 min after the last
   A051E41E input (not after 1 h), so a >12 min idle with no A051E41E input is a clean success
   criterion for A1 (no `Display Sleep: Disconnecting`, no VHID cancellation).
2. **A1 must not assume UC keeps the display awake** (new A6). UC's assertion follows its input
   session, not `GlueIdleTimeout`. Folded as a binding requirement into A1 and C1.
3. **C1 shows both owners** of `PreventUserIdleDisplaySleep` (vdisp *and* UniversalControl),
   so the two are never conflated.
4. **New item A5** (recover from a display-sleep disconnect without `-501`): wake displays,
   wait for self-reconnect, wait for the residual display to clear, abort instead of a doomed
   connect. Offline-verified via the harness (stub `dispid`/`connected`/`caffeinate`).
5. **New risk treated**: display sleep is itself a transition that costs UC *and* can leave a
   residual Sidecar display → `-501`. `up` handles it (A5); `doctor` recognises the distinct
   "Sidecar waiting for display wake" state instead of mis-reporting it as a zombie.
6. **Execution order**: A5 added to phase 1 (after A4, grouped with the other `up` changes);
   A1 stays in phase 2 but is declared the first live item (see rationale).
7. **Commit list**: +A5; A6 folded into the A1 and C1 commits (no separate commit).

---

## Goals (v4)

1. Stop causing Universal Control drops the tools do not need to cause (A2, A3, A4, A5).
2. Keep the displays awake for the life of a *live* Sidecar session, keyed on evidence of a live
   session — **and never rely on UC's own assertion** (A1 + A6).
3. Recover from a display-sleep disconnect without a doomed `-501` connect (A5).
4. Fix the correctness gaps found in review (B1, B2, B4, B6).
5. Make the factors we cannot control visible (C1), and calibrate what "a drop" means to the user
   before trusting the proxies.

## Non-goals (v4)

- Changing UC defaults (`GlueIdleTimeout`, `AutomaticallyReconnect`): user decision (T2).
- Layout A/B (T5): deferred.
- Moving the recorder into `tools/`: deferred.
- Modifying `SidecarLauncher/main.swift`: unchanged; timeouts live in the wrapper.
- Touching `watch/`, `UC-DROPS.md`, `IMPLEMENTATION-PLAN.md`, or the `docs/uc-hardening/` base
  files (`analysis.md`, `plan.md`, `design-v3.md`).
- No `up`/`down`, no `vdisp`/LaunchAgent restart, no `install.sh` during the offline phase.

## Prior reviews (carried over from v3, unchanged)

- **Round 1 (7/7 accepted)**: A2 gate drops the mode comparison; A1 evidence-not-duration; A1 probe
  on a serial queue with a main-queue timeout; A3 extended poll + `unknown`-no-reconnect; A4
  `exec`/flag/`|| rc=$?`; live pass/fail split; phase-2 deploy sequence (restart-vdisp → install).
- **Round 2 (3/3 accepted, all annotations)**: staged-`main.swift` build mechanism for B1; two
  named selectors (`live_sidecar_line` no-fallback, `any_sidecar_line` with fallback); three-state
  A2 gate (probe `unknown` + live line → no reconnect + warn); A1 discriminator
  (`mv bin/connected`); A1 probe-timeout timer on main + `stopping` flag; A4 sentinel file +
  env-overridable constants; B7 rewrites `usage_up` + "What it does"; `restart-vdisp` as a gate +
  `RESTART_TIMEOUT=30`; open-lid geometry `mirror_of == builtin.id`; PD window `[PD-60s, PD+5s]`.
  The full text of these resolutions lives in `design-v3.md`; they are not changed by v4.

---

## Execution order (v4)

| phase | items | deployment | verifiable |
|---|---|---|---|
| 1 — offline | harness (`SIDECAR_BIN`), B4, A2, A3, A4, **A5**, B1, B2, B3, B5, C1 | none (build + `bash -n` + harness) | offline |
| 2 — live, sequenced | **A1** + B6 (A1 first; B6 is its enabler) | one restart sequence | live |
| 3 — docs | B7 | none | offline |

**Why A5 is in phase 1.** A5 is a pure `bin/sidecar` change (`caffeinate` + two polls), fully
testable offline with the harness (stub `dispid`/`connected`/`caffeinate`). It depends only on B4's
`live_sidecar_line`/`any_sidecar_line`, already first among the functional items. Grouping it with
the other `up` changes (A2/A3/A4) keeps the shell refactor in one offline pass.

**Why A1 stays in phase 2.** A1 is live-only: it edits `vdisp.swift` and its only meaningful
verification requires a live session and a `vdisp` restart. It cannot enter the offline phase, and
it must stay batched with B6 — a separate A1-first restart would cost a second restart (and a
second `-501` risk) for no benefit. The 12:12 event raises A1's priority *within* the live phase
(it is now the primary justification for the cycle and the first thing deployed), not its phase.

---

## Item by item

### Harness + `SIDECAR_BIN` (offline)

**Change.** New `tools/tests/`: stubs for `SidecarLauncher`, `connected`, `dispid`, `vdisp`,
`arrange`, `mirror`, `setmode`, `dispmode`, **`caffeinate`** (added for A5), driven by env vars
(exit code / output / sleep / "display appears after N calls"). `tools/tests/run.sh` runs
`bin/sidecar` with `BIN` pointing at the stubs. `bin/sidecar` gains one test-only override:

- `SIDECAR_BIN` unset → `BIN` derived from the script path **exactly as today**.
- `SIDECAR_BIN` set and a directory → `BIN="$SIDECAR_BIN"` (and `TOOLS`/`LOGS`/`RES_FILE` derive
  from it, so the harness stays off the real `logs/` and `state/`).
- `SIDECAR_BIN` set but not a directory → `fail` with a one-line
  `ERROR: SIDECAR_BIN is set but not a usable directory: …`, exit non-zero, no fallback.

**Acceptance [offline].** Unset → identical to today. Invalid → loud error, non-zero. Temp dir →
all helpers resolve from it; the A2–A5 cases below pass.

**Regression risk.** Low; opt-in and the loud-fail path cannot mask a typo.

### B4 — `dispid` exposes mirroring; two selectors; `doctor` distinguishes "waiting for wake"

**Change.** `dispid.swift`: add `active=<bool> mirror_of=<id>` **before** the resolution (the
resolution stays last — `resolution()` reads `$NF`). New line:
`id=… vendor=… model=… serial=… builtin=… main=… active=… mirror_of=… WxH`.

`bin/sidecar` gains two distinct selectors, both parsing the new fields:

- **`live_sidecar_line`** — the Sidecar line with `active=true` **or** `mirror_of=<id>` where
  `<id> != 0`; highest id among candidates; **no fallback** — empty when no such line exists. Used
  by A2, A3, A5, B5, and the geometry test. This is the only "live" notion.
- **`any_sidecar_line`** — the first Sidecar line, with fallback (may be a zombie). Used **only**
  to describe in `status`/`doctor`, for the stale-display abort in `cmd_up`, and by A5's residual-
  display wait.

`virtual_line` (vendor `0x5644` with `main=true`, fallback first) is unchanged. Vendors anchored
with `([[:space:]]|$)`. `status`: `mirror: sidecar N -> M` from `dispid`; keep `mirror_state` only
as fallback.

**`doctor` — the Sidecar state, using the probe and the two selectors** (replaces the old
mirror-based check; removes the unused `sline` local):

- probe `connected` + `live_sidecar_line` present → `ok "Sidecar is connected and its display is
  live"`.
- probe `connected` + `any_sidecar_line` present but `live_sidecar_line` empty →
  **`"Sidecar session suspended: waiting for display wake (display N, active=false, mirror_of=0)"`**.
  This is a **distinct state, not a zombie** (the device is still associated; `disconnect` is
  accepted without `-102`). Fix: `caffeinate -u -t 2`, or `sidecar up` (A5 wakes and waits).
- probe `disconnected` + `any_sidecar_line` present → `"Sidecar display is orphaned"` (zombie).
  Fix: lid cycle (unchanged).
- probe `connected` + no Sidecar display listed → `"device connected, no display listed yet"`.

The discriminator between "waiting for wake" and "zombie" is the **probe** (connected = a suspended
session still owns the device; disconnected = no owner), combined with **live vs any** display line.
Lid closed, `doctor` still requires `virtual.main==true && live_sidecar_line.mirror_of==virtual.id`
for the arrangement check.

**Acceptance [offline]** build + `bash -n` + a dispid-output fixture through the harness, including:
"zombie present, no live line" (`live_sidecar_line` empty, `any_sidecar_line` non-empty) and the
"suspended session" fixture (probe `connected` + `any_sidecar_line` + `live_sidecar_line` empty →
the suspended-state message, not the zombie message). **[live]** `time sidecar doctor` < 1 s, no
`system_profiler`, `consistent`.

**Regression risk.** Medium: `doctor`/`status` output changes. The added fields are append-only and
every existing grep in `bin/sidecar` anchors on `key=value` or `$NF`, so the format change is
compatible. Recorder ignores `status:`/`doctor:` lines.

### A2 — idempotent `up` (offline)

**Change.** In `cmd_up`, after `cmd_ensure` and the stale-display check, a **three-state gate**:

- `live = live_sidecar_line()` (no fallback), `probe = sidecar_probe_state`.
- Geometry (lid closed): `virtual.main==true && live.mirror_of==virtual.id`; (lid open):
  `builtin_present && live.mirror_of==builtin.id` (the built-in's id, not "any master").
- Skip the reconnect iff `live` is non-empty **and** `probe ∈ {connected, unknown}` and no
  `--force`:
  - `probe == connected` → `info "session healthy (id=…): no reconnect"`.
  - `probe == unknown` → `warn "probe unavailable: assuming the live display is the session; use
    --force to reconnect"`.
  - then run the layout step (`arrange`/`mirror`, idempotent); if geometry is not ok, the layout
    step fixes it **without a reconnect**; return 0.
- Otherwise → the A5 recovery path, then today's full path (disconnect, pass 1, optional pass 2).
  The `state/resolution` vs `current_sidecar_mode` comparison is **removed** from the gate: with
  the always-mirrored arrangement the Sidecar's own mode is irrelevant to what is shown, and the
  only path that reapplies a saved mode is `up --force`. `main()` accepts `--force` for `up`;
  update `usage_up` and README (B7).

**Acceptance [offline, harness].** `connected` exit 0 + live line → rc 0, no `connect` /
`disconnect` line, arrange/mirror stub invoked. `connected` exit 3 + live line → rc 0, **0**
connects, a WARN. `connected` exit 3 + no live line → reconnect (1 connect). `connected` exit 1 +
live line → reconnect. `--force` → exactly one disconnect + one connect.

**Regression risk.** Low; the fast path still runs the layout step, so a healthy-but-misarranged
session is corrected without a reconnect.

### A3 — no reconnect storms (offline)

**Change.** In `connect_with_retries`, after `connect` exit 0 with no **live** line
(`live_sidecar_line` empty) after `CONNECT_SETTLE`:

- Poll up to `CONNECT_DISPLAY_WAIT=25` s for `live_sidecar_line()`.
- Live line appears → connected, success (success is **only** the live line, never a zombie).
- On expiry, branch on the probe:
  - `connected` → `fail` (stale-display signature: session claims connected, no live display). No
    reconnect.
  - `disconnected` → count a *flap*. Two flaps in one `up` → `fail` with the stale-display /
    iPad-held-elsewhere message.
  - `unknown` → `fail "connect returned ok but the session state is unknown (probe unavailable)"`.
    No reconnect.
- Keep the existing classification for non-zero exits.

**Acceptance [offline, harness].** exit 0 + probe `disconnected` twice → abort, exactly 2 connects.
exit 0 + probe `connected` + no live line after 25 s → fail, 1 connect. exit 0 + probe `unknown` →
fail, 1 connect, no reconnect. exit 0 + fixture "zombie present, no live line" → fail (the zombie
is not a success).

**Regression risk.** Low; only changes a path that today reconnects after an apparent success.

### A4 — timeouts + exit-3 classification (offline)

**Change.** `bin/sidecar` only. `run_with_timeout SECONDS cmd…` (bash 3.2, no `timeout(1)`):

- Run `( exec "$@" ) > "$out" 2>&1 &`; `pid=$!` (the background PID is the command itself).
- Watchdog `( sleep "$secs" && touch "$flag" && kill -TERM "$pid" 2>/dev/null ) &`; `watchdog=$!`.
- `wait "$pid" || rc=$?` — the errexit-safe form (the `||` swallows the non-zero `wait`); the
  timeout is detected by the **sentinel file** `$flag` (a subshell cannot propagate a variable to
  the parent), never by the rc (a TERM-killed process returns 143).
- If `[ -f "$flag" ]` → `rc=124`; else keep `$rc`. Kill `$watchdog`, clean `$out` and `$flag` on
  both paths; never kill the process group.

Use for `connect` (`CONNECT_TIMEOUT=30`) and `disconnect` (`DISCONNECT_TIMEOUT=15`).
`classify_connect`: `rc 124` → a dedicated branch: **probe first** — if `connected`, do not
reconnect (the daemon may have completed the connect while the CLI was killed), poll for the live
line and treat its appearance as success, else `fail`; otherwise retry with `TIMEOUT_RETRY_DELAY=10`.
`rc 3` ("not in the list of available devices") → `retry`. Keep the
`connect "<NAME>" exit <rc>: …` log format.

Timing constants are **env-overridable** (`CONNECT_TIMEOUT`, `DISCONNECT_TIMEOUT`,
`CONNECT_ATTEMPTS`, `CONNECT_SETTLE`, `CONNECT_DISPLAY_WAIT`, `WAKE_SETTLE`, `RETRY_DELAY`,
`TIMEOUT_RETRY_DELAY`, `VDISP_TIMEOUT`, `DOWN_TIMEOUT`, `RESTART_TIMEOUT`) so the harness can
shrink them. Worst-case ceiling ≈ `CONNECT_ATTEMPTS × (CONNECT_TIMEOUT + TIMEOUT_RETRY_DELAY) +
CONNECT_DISPLAY_WAIT` ≈ 225 s (≈ 330 s if every attempt is charged both timeout and display-wait);
the harness overrides to run in seconds.

**Acceptance [offline, harness].** Stub sleeping 60 → `up` gives up after `CONNECT_ATTEMPTS × 30 s`
with clear messages. Stub exit 3 twice then 0 → connected at attempt 3. Stub exit 124 with probe
`connected` → no second connect; probe `disconnected` → retried once.

**Regression risk.** Low; a 30 s bound only makes failures faster. The watchdog must not orphan and
the temp files must be cleaned.

### A5 — recover from a display-sleep disconnect without `-501` (offline)

**Why.** 2026-11-03 13:17:45: after `Display Sleep: Disconnecting`, Sidecar kept a session waiting
to reconnect on display wake, and the old Sidecar display 23 stayed listed. `up` disconnected that
session (accepted, no `-102`) and its connect failed with `-501` because display 23 still occupied
the slot. The stale-display check did not fire because the probe did not say `disconnected`.

**Change.** In `cmd_up`, when the A2 gate did **not** find a healthy session, **before**
`disconnect_quiet`:

1. **Wake the displays**: `caffeinate -u -t 2` (declares user activity; no sudo).
2. Wait up to `WAKE_SETTLE=10` s for Sidecar to reconnect by itself: poll `sidecar_probe_state`
   and `live_sidecar_line`. If the live line appears, the suspended session reconnected → proceed
   to the layout step (as A2), no reconnect.
3. If not reconnected, and `any_sidecar_line` is still listed while the probe is **not**
   `connected` (the suspended session ended and left a display behind), wait up to `WAKE_SETTLE`
   more for the display to disappear (poll `any_sidecar_line`).
4. If it disappeared → fall through to `disconnect_quiet` + `connect_with_retries` (normal path).
5. If it stays (zombie persists) → `fail` with the existing stale-display message: **do not spend
   a connect on `-501`**.

**Acceptance [offline, harness].** A `dispid` stub that lists a Sidecar display for the first N
calls and a `connected` stub that returns `connected` after the wake → no connect, "session
healthy". A `connected` stub that stays `disconnected` and a `dispid` stub that keeps listing the
Sidecar → abort with the stale-display message, **0** connects (no `-501`).

**Regression risk.** Low; the only new external call is `caffeinate -u -t 2`, idempotent and safe
without sudo, and it runs only on the non-healthy path (never on a healthy `up`). The wake is a
2 s user-activity nudge, harmless on an already-awake display.

### B1 — shared display-selection rule (offline build, live assert)

**Change.** New `src/disprule.swift`, **declarations only** (no top-level statements):
`onlineList() -> [CGDirectDisplayID]`, `selectSidecar(_:) -> CGDirectDisplayID?`,
`selectVirtual(_:) -> CGDirectDisplayID?`.

- **Sidecar** (`0x6161706c`): online, prefer `CGDisplayIsActive != 0 ||
  CGDisplayMirrorsDisplay != 0`; among those, highest id.
- **Virtual** (`0x5644`): online, prefer `CGDisplayIsMain != 0`, then active, then largest.

`arrange.swift` replaces "first Sidecar" (~:35) and "largest virtual" (~:41); `setmode.swift`,
`dispmode.swift`, `mirror.swift` switch `CGGetActiveDisplayList` → `CGGetOnlineDisplayList`.

**Build mechanism (exact).** Multi-file `swiftc` only permits top-level code in a file named
`main.swift`, so `build.sh` stages the helper source under that name and compiles it with the
shared file:

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
single-file as today (unchanged). Stage dirs are removed on EXIT (extend the existing trap).

**Acceptance [offline]** build + `bash -n` (the staged-`main.swift` compile is the proof).
**[live]** `bin/dispmode` lists the Sidecar while it mirrors; `bin/setmode 1321x918` finds it;
`sidecar res` shows its modes.

**Regression risk.** Low for the read helpers. `mirror` runs only when a built-in is present; its
idempotence lands in B2, so keep B1→B2 order.

### B2 — `mirror` reports failure and is idempotent (offline-only this cycle)

**Change.** `mirror.swift`: use the B1 rule; drop `0x756e6b6e` (headless framebuffer) from
`isSidecar`. If `CGDisplayMirrorsDisplay(sidecar) == builtin`, print `already mirrored: sidecar N
-> builtin M` and exit 0. Exit 1 when `CGConfigureDisplayMirrorOfDisplay` or
`CGCompleteDisplayConfiguration` is not `.success` (today it always exits 0).

**Acceptance [offline]** build + logic review (idempotence short-circuit, exit-code paths). Live
exercise deferred to a lid-open session; declared offline-only because closed-lid `up` never calls
`mirror` (`builtin_present` is false).

**Regression risk.** Low; makes `up` fail honestly instead of printing "mirror applied" on failure.

### B3 — `arrange` exit 3 on unclean result (offline) — cuttable

**Change.** `arrange.swift` phase 4 (~:128): exit **3** for "applied but not clean". In `cmd_up`:
rc 3 → `warn "arrange applied but not verified (see logs/arrange.log)"`; other non-zero → today's
warning; 0 → today's info.

**Acceptance [offline]** harness stub returns 3 → WARN (not INFO).

**Regression risk.** None (reclassifies a warning). Cut candidate.

### B5 — `res` explains a mirrored Sidecar (offline) — cuttable

**Change.** `res_show` and `cmd_res`: if `live_sidecar_line` has `mirror_of≠0`, print
`note: Sidecar mirrors display N; the iPad shows display N (VDISP_WIDTH/HEIGHT), not this mode.`
Still allow `res WxH` (remembered for the next session). Uses the live selector.

**Acceptance [offline]** fixture with `mirror_of≠0` → note printed.

**Regression risk.** None (output-only). Cut candidate.

### C1 — `status`/`doctor` show UC defaults, **both** assertion owners, and probe state (offline, info-only)

**Change.** Read-only, `info` only, no FAIL rule this cycle. **A6 applies**: show *both* owners of
`PreventUserIdleDisplaySleep` — `vdisp` and `UniversalControl` — so it is never implied that UC
alone keeps the display awake.

- `status`: `uc defaults: GlueIdleTimeout=… AutomaticallyReconnect=…` from
  `defaults read com.apple.universalcontrol <key> 2>/dev/null` (else `unset`); `display awake:
  <owner list>` = **all** owners of `PreventUserIdleDisplaySleep` parsed from
  `pmset -g assertions` (typically `vdisp, UniversalControl`); and
  `keep-awake: <last keep-awake line from logs/vdisp.out.log>` — the only channel that surfaces
  A1's `probe=timeout` / `probe=3` / `probe=ok` state.
- `doctor`: an `info` line with the UC defaults and the display-awake owner list.

**Parsing rule (hard).** `pmset -g assertions` output is not contractual: if the expected
section/keys/owner names are absent or `pmset` fails, print `unknown` / `none`. Never synthesize a
value; never infer an owner from a pid not present in the section. The deferred FAIL rule ("vdisp
does not hold the assertion while A1 is enabled") has no reliable "A1 enabled" source and a 30 s
post-`down` false-positive, so it is out of scope this cycle.

**Acceptance [offline]** harness feeds a recorded `pmset -g assertions` fixture + stubbed `defaults`
→ correct `unknown`/value output in the malformed and empty cases; the multi-owner fixture shows
`vdisp, UniversalControl`. **[live]** phase 2: `status` shows the real owner list and the
keep-awake/probe line.

**Regression risk.** Low (read-only). The `unknown`-never-invent rule is the only hard requirement.

### A1 — keep displays awake for a *live* session, independent of UC (live, sequenced with B6)

**Change.** `vdisp.swift` + `daemon/local.sidecar.vdisp.plist.in`.

Hold `kIOPMAssertionTypePreventUserIdleDisplaySleep` (`"local.sidecar.vdisp: Sidecar session"`)
while a live session is evidenced. **Evidence, not duration, and never assuming UC (A6):**

- Hold iff `VDISP_KEEP_AWAKE != "0"` (default on) **and** `connected` exits 0 **and** an online
  display with vendor `0x6161706c` exists (`CGGetOnlineDisplayList`).
- Release iff any term fails: env off, `connected` exits 1 (disconnected), probe unavailable
  (spawn fails / missing binary / **`probe=timeout`** / exit 3 — all **fail-safe: release**), or no
  online Sidecar display.
- Optional absolute backstop `KEEP_AWAKE_MAX_HOLD` (default `0` = off; a large value such as
  `86400` if a hard ceiling is wanted). Its clock resets on an observed release *or* on a change of
  the online Sidecar display id. It does not fire on healthy sessions by default.

**Why it cannot rely on UC (A6).** The 12:12 event shows UC releases its own
`PreventUserIdleDisplaySleep` ~10 min after the last A051E41E input session ends (12:11:34, after
12:01:44), and the display sleeps 32 s later — `GlueIdleTimeout=3600` does **not** guarantee a hold.
`vdisp`'s assertion is the only one owned by the session itself; C1 shows both owners so the two
are never conflated.

**Concurrency.** A dedicated serial `probeQueue` runs the probe via `Process.waitUntilExit()`.
The ~5 s timeout is a `DispatchSourceTimer` on the **main** queue (it calls `process.terminate()`,
thread-safe, and sets a `probeTimedOut` flag), **not** on `probeQueue` (which is blocked in the
wait and would never fire the timer). Timeout is logged `probe=timeout`, distinct from `probe=3`.
The `CGDisplayRegisterReconfigurationCallback` callback only does `probeQueue.async { evaluate() }`.
A 30 s `DispatchSourceTimer` also enqueues `evaluate()`. The assertion create/release is applied on
the main queue. A `stopping` flag is set by B6's signal handler before release; the `evaluate()`
completion checks it and skips the assertion-create while set, so an in-flight probe cannot re-take
the assertion during the 0.5 s exit window.

**Logging.** Each transition to stdout (`logs/vdisp.out.log`, not `sidecar.log`): `keep-awake on
(connected=N)`, `keep-awake off (probe=<rc|timeout> | no sidecar display | env)`, `keep-awake off
(backstop)`.

**Template.** Add `<key>VDISP_KEEP_AWAKE</key><string>1</string>` under `EnvironmentVariables`.

**Acceptance [live].**

- **Mechanism.** Session up: `pmset -g assertions` lists `PreventUserIdleDisplaySleep` owned by
  `vdisp` (by name), alongside UC — both visible in `status` (C1/A6). Discriminator:
  `mv bin/connected bin/connected.off` → the assertion disappears ≤30 s (fail-safe on probe
  unavailable) → `mv` back → the assertion returns. `VDISP_KEEP_AWAKE=0`: never held.
- **Outcome (mandatory, from the 12:12 event).** With A1 on and a live session, confirm the
  recorder shows **no A051E41E VHID activity** in the window, then idle **> 12 min** (exceeding the
  observed 12:11:34 → 12:12:06 window). **Success**: no `Display Sleep: Disconnecting`, no VHID
  cancellation of A051E41E, no `UC ACTIVE→IDLE` release of the *vdisp* hold. **Failure**: the 12:12
  event repeats (UC releases, display sleeps, session closes, VHID cancels). This replaces the v3
  "outcome deferred to T3" clause — the event made the test reproducible and discriminating (UC
  drops its assertion ~10 min after input ends, so a >12 min idle separates A1 from UC).

**Regression risk.** `vdisp` is the display owner: a crash drops the display and the session dies at
the next lid close. Mitigated: the probe path is isolated on its own queue with a main-queue
timeout, every failure releases (never throws), and the backstop is off by default.

### B6 — `vdisp` handles SIGTERM explicitly; install sequence (live, sequenced with A1)

**Change.** `vdisp.swift`: `signal(SIGTERM, SIG_IGN)` and `signal(SIGINT, SIG_IGN)`, then
`DispatchSource.makeSignalSource` for both. On fire: (1) set `stopping`; (2) release the A1
assertion synchronously (never waiting on the probe queue); (3) drop the display reference
(`var display: NSObject?` set to `nil`); (4) wait 0.5 s on the main queue; (5) `exit(0)`.
Template: add `<key>ThrottleInterval</key><integer>10</integer>`.

`install.sh`: after `bootout`, poll ≤10 s for the old pid to disappear before `bootstrap`; if
`bootstrap` fails, wait and retry once.

This makes "SIGTERM releases the display" true by construction. After B6, `bootout` (which sends
SIGTERM) is safe **once the new binary is running**; `SIGKILL` / `kickstart -k` still cannot run any
handler and still orphan.

**Deployment sequence (mandatory, live):** `./build.sh` → `sidecar restart-vdisp` (SIGTERM the old
process; KeepAlive restarts the **new** binary) **as a hard gate** → `./install.sh` (bootout now
hits the new handler; poll for pid; bootstrap; retry once).

**Acceptance [live].** `sidecar restart-vdisp` leaves exactly one `0x5644` display in `bin/dispid`
and `vdisp.out.log` shows the shutdown line — this post-condition is a **gate**: if it does not
hold, stop and do not run `install.sh`.

**Regression risk.** Medium: a handler that fails to release before `exit` re-orphans. Verified by
"exactly one `0x5644`". Order after A1 (it releases A1's assertion).

### B7 — README + `usage_up` (offline, last)

- Rewrite the "SIGTERM releases / SIGKILL does not" rule to describe the B6 handler (releases
  assertion + drops display ref + waits) and state that `bootout` is safe once B6 is running, while
  `SIGKILL` / `kickstart -k` still orphan.
- Remove/qualify the "~1 min vs ~4 min" UC figure in **three places**: `README.md` ~68–69,
  `README.md` ~366, and `bin/sidecar` `usage_up` ~269–271. Link `UC-DROPS.md` instead.
- Rewrite the `up` flow in `usage_up` steps 3–7 and the README "What it does" line, which describe
  an unconditional disconnect+connect+setmode that A2 no longer runs; state that `up` is idempotent
  (skips reconnect when healthy), that the only path that reapplies a saved mode is `up --force`,
  and that `up` now wakes the displays and waits for a suspended session before connecting (A5).
- Document `VDISP_KEEP_AWAKE` (+ `KEEP_AWAKE_MAX_HOLD`), `up --force`, the timeouts, the new
  `dispid` fields, `SIDECAR_BIN` (test-only), the perceived-drop marker, and the "Sidecar waiting
  for display wake" `doctor` state.
- Known limits: "every switch of the iPad between Macs costs one UC drop per transition (OS
  behaviour)".

---

## Operational definition of "perceived drop", and the live-verification protocol

**Definition.** A **perceived drop (PD)** is the moment the user, actively typing or clicking from
the work Mac (`IDS A051E41E`), notices input stop on the personal Mac. It is the only ground truth.
`Peer appears missing` (UC↔iPad link) and `VHID … Canceling Service` (A051E41E input link) are
proxies that the data show can fire *without* a perceived drop (the reverse is not established).

**Who annotates.** The user, at the moment of noticing. The agent cannot perceive a drop.

**Format.** One line, ISO timestamp first, to `tools/logs/perceived.log` (git-ignored):
`<ISO8601 ts> perceived-drop <free-text note>` via
`printf '%s perceived-drop %s\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" "$note" >> tools/logs/perceived.log`.
No new CLI command. Documented in B7.

**Comparison.** For each PD, read the recorder window `[PD-60s, PD+5s]` and attribute it to the
nearest trigger. If no trigger falls in the window, mark the PD **unexplained** (do not
force-attribute). Calibration target is the A051E41E input link; the iPad link is corroborating
only.

**Scheduled resets.** The live phase performs, in order:

1. `./build.sh` → no session impact.
2. `sidecar restart-vdisp` — **gate** (exactly one `0x5644`, new pid, shutdown line) → 1 reset.
3. `./install.sh` → 1 reset.
4. `sidecar up` → 1 reset.
5. `sidecar up` again → **0** resets (A2 proof; any recorder event fails).
6. A1 discriminator (`mv bin/connected` off/on) → 0 resets.
7. `sidecar status` / `doctor` → 0 resets (both owners shown, suspended state recognised).
8. **A1 outcome idle test (mandatory)** → 0 resets: confirm no A051E41E VHID activity, idle
   > 12 min, assert no `Display Sleep: Disconnecting` and no VHID cancellation.
9. `sidecar down` → 1 reset (proves A1 release with a stale display lingering).

**Pass/fail (falsifiable).**

- **Objective pass**: the recorder shows no iPad-link reset outside the scheduled step windows
  (2, 3, 4, 9); step 5 produces zero events; step 2's gate holds; step 8 passes; step 9 shows A1
  released ≤30 s.
- **PD overlay**: a PD outside the scheduled windows = **failure**; a PD inside a scheduled window =
  evidence about the two-link model (recorded, not a failure); a PD with no trigger in
  `[PD-60s, PD+5s]` = unexplained, reported.
- A051E41E `Canceling Service` is corroboration only, never a pass/fail criterion **except** as the
  step-8 outcome signal (there it is the measured effect of A1).
- **A1**: proof is **mechanism** (named assertion + discriminator) **and outcome** (step 8), the
  latter now mandatory.
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
- `connected.swift` stays the single source of truth for "live session"; A1 and the shell consume
  it, so a future probe change is one edit.
- `src/disprule.swift` is the single source of the display-selection rule.

---

## Commits (one per item, English, `Verify:` paragraph)

1. `test: add offline harness and SIDECAR_BIN override`
2. `feat(dispid): expose active/mirror_of; add live/any sidecar selectors` (B4)
3. `feat(up): make up idempotent with --force and probe-unknown policy` (A2)
4. `fix(up): stop reconnect storms after a connect-then-close` (A3)
5. `fix(up): bound connect/disconnect with timeouts, retry exit 3` (A4)
6. `fix(up): wake displays and recover from a sleep-disconnect without -501` (A5)
7. `refactor: shared display-selection rule via staged main.swift` (B1)
8. `fix(mirror): report failure and short-circuit when already mirrored` (B2)
9. `fix(arrange): exit 3 when the arrangement is not verified` (B3, cuttable)
10. `feat(res): explain a mirrored Sidecar` (B5, cuttable)
11. `feat(status,doctor): show UC defaults, both display-awake owners, and probe state` (C1 + A6)
12. `feat(vdisp): keep displays awake for a live session, independent of UC` (A1 + A6)
13. `fix(vdisp): handle SIGTERM explicitly; throttle KeepAlive; install waits for pid` (B6)
14. `docs: correct SIGTERM/bootout rule, UC figures, and the up flow` (B7)

Deployment note: commits 12 and 13 are deployed together in the sequence
`build.sh → restart-vdisp (gate) → install.sh`; every other commit is build/`bash -n`/harness-
verified without touching the session. A6 is a binding note folded into commits 11 and 12 (no
separate commit).
