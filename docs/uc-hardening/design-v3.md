# UC hardening design — v3

Base: branch `uc-hardening` @ `7cbf7ee`. Reuses the item IDs of `IMPLEMENTATION-PLAN.md`
(A1–A4, B1–B7, C1). v3 incorporates the second adversarial review (three new blocking objections
accepted, none rejected) and the medium/low annotations, on top of v2 (first review: 7/7 accepted).

## Goals

1. Stop causing Universal Control drops the tools do not need to cause (A2, A3, A4).
2. Keep the displays awake for the life of a *live* Sidecar session, keyed on evidence of a live
   session, not on display presence and not on a duration that punishes healthy sessions (A1).
3. Fix the correctness gaps found in review (B1, B2, B4, B6).
4. Make the factors we cannot control visible (C1), and calibrate what "a drop" means to the user
   before trusting the proxies.

## Non-goals

- Changing UC defaults (`GlueIdleTimeout`, `AutomaticallyReconnect`): user decision (T2).
- Layout A/B (T5): deferred.
- Moving the recorder into `tools/`: deferred.
- Modifying `SidecarLauncher/main.swift`: unchanged; timeouts live in the wrapper.
- Touching `watch/`, `UC-DROPS.md`, `IMPLEMENTATION-PLAN.md`.
- No `up`/`down`, no `vdisp`/LaunchAgent restart, no `install.sh` during the offline phase.

---

## Resolution of the second review

**1. B1 — `disprule.swift` "alongside each helper" does not compile — ACCEPTED.**
Correct: with `swiftc` multi-file, top-level code is only legal in a file named `main.swift`, and
the four helpers are entirely top-level. Fixed with the staged-`main.swift` mechanism (below,
"Build mechanism"). `-parse-as-library` + `@main` is rejected as more invasive (it changes the
shape of four working files for no functional gain).

**2. B4/A2/A3 — `live_sidecar_line` with "fallback first" is not live — ACCEPTED.**
A single zombie display is returned by the fallback and would read as "live". Fixed: two distinct,
named selectors — `live_sidecar_line` (no fallback, empty unless `active=true` or `mirror_of≠0`)
and `any_sidecar_line` (with fallback, for description and the stale-display abort only).

**3. A2 — probe `unknown` silently falls back to reconnect every `up` — ACCEPTED.**
`bin/connected` exits 3 when the private API changes (a README-documented expected state). Fixed:
a three-state gate — `unknown` + live line → no reconnect + warn; `unknown` + no live line →
reconnect; plus a harness case.

**Annotation A1 — "released within 30 s" is not discriminating — ACCEPTED.**
After `down`, probe and display fail together, so the acceptance does not prove the condition is
the probe. Added a discriminator: `mv bin/connected bin/connected.off` → assertion must disappear
≤30 s (fail-safe on probe unavailable) → `mv` back → assertion must return.

**Annotation A1 — probe timeout timer cannot live on the serial `probeQueue` — ACCEPTED.**
A timer on the queue blocked in `waitUntilExit` never fires. Fixed: the ~5 s timeout is a
`DispatchSourceTimer` on the **main** queue (calls `process.terminate()`, which is thread-safe);
`probe=timeout` is logged distinct from `probe=3`; both are surfaced in `status` (C1, info-only,
is the only channel). Added a `stopping` flag so an in-flight `evaluate()` cannot re-take the
assertion during B6's 0.5 s exit window.

**Annotation A4 — errexit/`wait`, sentinel, worst case, env overridable — ACCEPTED.**
`wait "$pid" || rc=$?` is the errexit-safe form and is the one specified; the timeout is a
**sentinel file** (a subshell cannot propagate a variable to the parent), not a variable; the
worst-case ceiling is stated and every timing constant is env-overridable so the harness stays fast.

**Annotation B7 — `usage_up` steps 3–7 and "What it does" describe a flow A2 no longer runs —
ACCEPTED.** Both are rewritten, and it is stated that with the idempotent gate the only path that
reapplies a saved mode is `up --force`.

**Annotation Fase 2 — criterion rephrase, `restart-vdisp` as a gate, `RESTART_TIMEOUT=30` —
ACCEPTED.** The objective criterion is "no iPad-link reset outside the scheduled step windows"
(PD is the subjective overlay); `restart-vdisp` becomes a hard gate (post-condition: exactly one
`0x5644`) before `install.sh`; `RESTART_TIMEOUT` 15 → 30 s.

**Annotation A2 — open-lid geometry: `mirror_of` must equal the built-in id, not "any master" —
ACCEPTED.**

**Coherence — ACCEPTED.** The "three" annotation count is corrected to four; phase-1 order is made
consistent everywhere (…B2, B3, B5, C1, with C1 last); the PD "and vice versa" claim is removed
(not supported by the data: the data show proxies firing *without* a perceived drop, never a
perceived drop *without* a proxy); the attribution window widens to `[PD-60s, PD+5s]`, with an
"unexplained" marker when no trigger falls inside it.

---

## Execution order (v3)

| phase | items | deployment | verifiable |
|---|---|---|---|
| 1 — offline | harness (`SIDECAR_BIN`), B4, A2, A3, A4, B1, B2, B3, B5, C1 | none (build + `bash -n` + harness) | offline |
| 2 — live, sequenced | A1 + B6 (`build.sh` → `restart-vdisp` gate → `install.sh`) | one restart sequence | live |
| 3 — docs | B7 | none | offline |

B4 is pulled ahead of A2/A3 because it provides the two selectors (`live_sidecar_line`,
`any_sidecar_line`) and the `active=`/`mirror_of=` dispid fields that A2/A3 use. B3 and B5 sit
before C1 (which is last, info-only) so they can be cut without disturbing any dependency. Phase 2
deploys A1+B6 in the objection-7 sequence, with `restart-vdisp` as a hard gate before `install.sh`.

---

## Item by item

### Harness + `SIDECAR_BIN` (offline)

**Change.** New `tools/tests/`: stubs for `SidecarLauncher`, `connected`, `dispid`, `vdisp`,
`arrange`, `mirror`, `setmode`, `dispmode`, driven by env vars (exit code / output / sleep /
"display appears after N calls"). `tools/tests/run.sh` runs `bin/sidecar` with `BIN` pointing at
the stubs. `bin/sidecar` gains one test-only override:

- `SIDECAR_BIN` unset → `BIN` derived from the script path **exactly as today**.
- `SIDECAR_BIN` set and a directory → `BIN="$SIDECAR_BIN"` (and `TOOLS`/`LOGS`/`RES_FILE` derive
  from it, so the harness stays off the real `logs/` and `state/`).
- `SIDECAR_BIN` set but not a directory → `fail` with a one-line
  `ERROR: SIDECAR_BIN is set but not a usable directory: …`, exit non-zero, no fallback.

**Acceptance [offline].** Unset → identical to today. Invalid → loud error, non-zero. Temp dir →
all helpers resolve from it; the A2–A4 cases below pass.

**Regression risk.** Low; opt-in and the loud-fail path cannot mask a typo.

### B4 — `dispid` exposes mirroring; two named selectors (offline)

**Change.** `dispid.swift`: add `active=<bool> mirror_of=<id>` **before** the resolution (the
resolution stays last — `resolution()` reads `$NF`). New line:
`id=… vendor=… model=… serial=… builtin=… main=… active=… mirror_of=… WxH`.

`bin/sidecar` gains two distinct selectors, both parsing the new fields:

- **`live_sidecar_line`** — the Sidecar line with `active=true` **or** `mirror_of=<id>` where
  `<id> != 0`; highest id among candidates; **no fallback** — empty when no such line exists. Used
  by A2, A3, B5, and the geometry test. This is the only "live" notion.
- **`any_sidecar_line`** — the first Sidecar line, with fallback (may be a zombie). Used **only**
  to describe in `status`/`doctor` and for the stale-display abort in `cmd_up`.

`virtual_line` (vendor `0x5644` with `main=true`, fallback first) is unchanged. Vendors anchored
with `([[:space:]]|$)`. `doctor` (lid closed): OK iff the virtual line is `main=true` **and** the
`live_sidecar_line` has `mirror_of=<virtual id>`; print both ids. Remove the unused `sline` local.
`status`: `mirror: sidecar N -> M` from `dispid`; keep `mirror_state` only as fallback.

**Acceptance [offline]** build + `bash -n` + a dispid-output fixture through the harness
(including a "zombie present, no live line" fixture: `live_sidecar_line` empty, `any_sidecar_line`
non-empty). **[live]** `time sidecar doctor` < 1 s, no `system_profiler`, `consistent`.

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
- Otherwise (probe `disconnected`, or `live` empty, or `--force`) → today's full path
  (disconnect, pass 1, optional pass 2). The `state/resolution` vs `current_sidecar_mode`
  comparison is **removed** from the gate: with the always-mirrored arrangement the Sidecar's own
  mode is irrelevant to what is shown, and the only path that reapplies a saved mode is
  `up --force`. `main()` accepts `--force` for `up`; update `usage_up` and README (B7).

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
`CONNECT_ATTEMPTS`, `CONNECT_SETTLE`, `CONNECT_DISPLAY_WAIT`, `RETRY_DELAY`,
`TIMEOUT_RETRY_DELAY`, `VDISP_TIMEOUT`, `DOWN_TIMEOUT`, `RESTART_TIMEOUT`) so the harness can
shrink them. Worst-case ceiling ≈ `CONNECT_ATTEMPTS × (CONNECT_TIMEOUT + TIMEOUT_RETRY_DELAY) +
CONNECT_DISPLAY_WAIT` ≈ 225 s (≈ 330 s if every attempt is charged both timeout and display-wait);
the harness overrides to run in seconds.

**Acceptance [offline, harness].** Stub sleeping 60 → `up` gives up after `CONNECT_ATTEMPTS × 30 s`
with clear messages. Stub exit 3 twice then 0 → connected at attempt 3. Stub exit 124 with probe
`connected` → no second connect; probe `disconnected` → retried once.

**Regression risk.** Low; a 30 s bound only makes failures faster. The watchdog must not orphan and
the temp files must be cleaned.

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

### C1 — `status`/`doctor` show UC defaults, assertion owners, and probe state (offline, info-only)

**Change.** Read-only, `info` only, no FAIL rule this cycle.

- `status`: `uc defaults: GlueIdleTimeout=… AutomaticallyReconnect=…` from
  `defaults read com.apple.universalcontrol <key> 2>/dev/null` (else `unset`); `display awake:
  <owners>` = owners of `PreventUserIdleDisplaySleep` parsed from `pmset -g assertions`; and
  `keep-awake: <last keep-awake line from logs/vdisp.out.log>` — this is the only channel that
  surfaces A1's `probe=timeout` / `probe=3` / `probe=ok` state (A1 is info-only).
- `doctor`: an `info` line with the UC defaults and display-awake owners.

**Parsing rule (hard).** `pmset -g assertions` output is not contractual: if the expected
section/keys/owner names are absent or `pmset` fails, print `unknown` / `none`. Never synthesize a
value; never infer an owner from a pid not present in the section. The deferred FAIL rule ("vdisp
does not hold the assertion while A1 is enabled") has no reliable "A1 enabled" source and a 30 s
post-`down` false-positive, so it is out of scope this cycle.

**Acceptance [offline]** harness feeds a recorded `pmset -g assertions` fixture + stubbed `defaults`
→ correct `unknown`/value output in the malformed and empty cases. **[live]** phase 2: `status`
shows the real owners and the keep-awake/probe line.

**Regression risk.** Low (read-only). The `unknown`-never-invent rule is the only hard requirement.

### A1 — keep displays awake for a *live* session (live, sequenced with B6)

**Change.** `vdisp.swift` + `daemon/local.sidecar.vdisp.plist.in`.

Hold `kIOPMAssertionTypePreventUserIdleDisplaySleep` (`"local.sidecar.vdisp: Sidecar session"`)
while a live session is evidenced. **Evidence, not duration:**

- Hold iff `VDISP_KEEP_AWAKE != "0"` (default on) **and** `connected` exits 0 **and** an online
  display with vendor `0x6161706c` exists (`CGGetOnlineDisplayList`).
- Release iff any term fails: env off, `connected` exits 1 (disconnected), probe unavailable
  (spawn fails / missing binary / **`probe=timeout`** / exit 3 — all **fail-safe: release**), or no
  online Sidecar display.
- Optional absolute backstop `KEEP_AWAKE_MAX_HOLD` (default `0` = off; a large value such as
  `86400` if a hard ceiling is wanted). Its clock resets on an observed release *or* on a change of
  the online Sidecar display id. It does not fire on healthy sessions by default.

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

**Acceptance [live, mechanism].**

- Session up: `pmset -g assertions` lists `PreventUserIdleDisplaySleep` owned by `vdisp` (by name,
  not just UC).
- **Discriminator (proves the condition is the probe):** `mv bin/connected bin/connected.off` →
  the assertion disappears ≤30 s (fail-safe on probe unavailable) → `mv` back → the assertion
  returns. Reversible, no session impact.
- `VDISP_KEEP_AWAKE=0`: never held.

**Outcome proof is deferred to T3** (UC-DROPS): today UC holds the same assertion (pid 1081 since
02:42), so no outcome window exists without a >70 min idle or the T2 defaults A/B.

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
  (skips reconnect when healthy) and that with the gate the only path that reapplies a saved mode
  is `up --force`.
- Document `VDISP_KEEP_AWAKE` (+ `KEEP_AWAKE_MAX_HOLD`), `up --force`, the timeouts, the new
  `dispid` fields, `SIDECAR_BIN` (test-only), and the perceived-drop marker.
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
7. `sidecar status` / `doctor` → 0 resets.
8. idle ≥ 12 min → 0 resets (regression smoke; does **not** prove A1 outcome).
9. `sidecar down` → 1 reset (proves A1 release with a stale display lingering).

**Pass/fail (falsifiable).**

- **Objective pass**: the recorder shows no iPad-link reset outside the scheduled step windows
  (2, 3, 4, 9); step 5 produces zero events; step 2's gate holds; step 9 shows A1 released ≤30 s.
- **PD overlay**: a PD outside the scheduled windows = **failure**; a PD inside a scheduled window =
  evidence about the two-link model (recorded, not a failure); a PD with no trigger in
  `[PD-60s, PD+5s]` = unexplained, reported.
- A051E41E `Canceling Service` is corroboration only, never a pass/fail criterion.
- **A1**: proof is **mechanism** (named assertion held/released on the evidence condition, plus the
  discriminator); **outcome** proof is deferred to T3 and out of this cycle.

---

## Cuts, and why

- **B5 first**: cosmetic `res` note; nothing depends on it.
- **B3 second**: `up` already warns when `arrange` fails; B3 only refines severity.
- **Never cut**: B1, B4 (real bugs), A2/A3/A4 (UC-drop causes), A1 (RC2b), B6 (SIGTERM claim).

## Extension points

- `KEEP_AWAKE_MAX_HOLD` and `VDISP_KEEP_AWAKE` (A1), `SIDECAR_BIN` (harness), the timing constants
  (A4).
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
6. `refactor: shared display-selection rule via staged main.swift` (B1)
7. `fix(mirror): report failure and short-circuit when already mirrored` (B2)
8. `fix(arrange): exit 3 when the arrangement is not verified` (B3, cuttable)
9. `feat(res): explain a mirrored Sidecar` (B5, cuttable)
10. `feat(status,doctor): show UC defaults, display-awake and probe state` (C1, info-only)
11. `feat(vdisp): keep displays awake for a live session` (A1)
12. `fix(vdisp): handle SIGTERM explicitly; throttle KeepAlive; install waits for pid` (B6)
13. `docs: correct SIGTERM/bootout rule, UC figures and the up flow` (B7)

Deployment note: commits 11 and 12 are deployed together in the sequence
`build.sh → restart-vdisp (gate) → install.sh`; every other commit is build/`bash -n`/harness-
verified without touching the session.
