# Implementation plan — `tools/` after the UC-drop analysis

Written 2026-11-03 for the agent that maintains `tools/`. Background and evidence are in
`UC-DROPS.md`; read its **Synthesis** and **Correction (10:25)** first. Base: branch
`sidecar-tools` at `7cbf7ee` (arrange on the online list, doctor fixed).

## Goals, in order

1. **Fewer Universal Control drops caused by us.** Every Sidecar role change of the iPad
   (connect, disconnect, close, sleep-disconnect, reconnect) costs at least one UC drop.
   The tools must never cause one that is not needed.
2. **The session must not depend on a UC default.** Today the display stays awake only
   because UniversalControl holds `PreventUserIdleDisplaySleep`, most likely thanks to
   `GlueIdleTimeout = 3600` (written by hand at 23:14 on 11-02). The tools should keep the
   display awake themselves while a Sidecar session exists.
3. **Correctness gaps found in review**: helpers that still miss a mirrored Sidecar, weak
   checks in `doctor`, exit codes that hide failures.

## Ground rules

- **Do not touch `watch/`, `UC-DROPS.md` or this file.** The recorder (`local.sidecar.watch`)
  measures the effect of these changes and must stay the same instrument while they land.
- **Keep the `tools/logs/sidecar.log` formats the recorder parses**
  (`watch/lib/toolline.awk`). Lines start with an ISO timestamp, then:
  - `connect "<NAME>" (attempt N/M)` → CONNECT
  - `disconnect "<NAME>" sent` or `disconnect "<NAME>" exit …` → DISCONNECT
  - `Sidecar connected …` → CONNECTED
  - `ERROR …` / `WARN …` prefixes
  - `status:` / `doctor:` prefixes (ignored by the recorder)

  New messages are fine. If one of these must change, say so in the commit message so the
  recorder can follow.
- **One commit per item** (IDs below), each with a `Verify:` paragraph saying what was run.
- **Every live connect costs a UC drop.** Batch the live tests at the end (section
  "Live verification") and keep their number as stated. Offline checks first.
- Bash stays 3.2-compatible where the code may run under launchd (`/bin/bash`); the CLI
  `bin/sidecar` runs under the user's shell, but do not add bash-4-only features without
  need.
- `shellcheck` is not installed; `bash -n` at least, or `brew install shellcheck` if the
  user agrees.

---

## Phase A — stop causing drops (highest value)

### A1. Keep the displays awake while a Sidecar display exists

**Why.** RC2b/RC3: `Display Sleep: Disconnecting` killed the session 8 times on 11-02.
Today it does not happen only because of a UC default (see goal 2).

**Where.** `tools/src/vdisp.swift` (it is already the long-lived, `KeepAlive` process that
owns the display lifecycle), `tools/daemon/local.sidecar.vdisp.plist.in`.

**Change.**
- Add an IOKit power assertion, held **only while an online display with vendor
  `0x6161706c` exists**:
  `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
  IOPMAssertionLevel(kIOPMAssertionLevelOn), "local.sidecar.vdisp: Sidecar session" as CFString, &id)`;
  release with `IOPMAssertionRelease(id)`.
- Re-evaluate on `CGDisplayRegisterReconfigurationCallback` (Sidecar display added or
  removed) **and** on a 30 s `DispatchSourceTimer` as a backup. Enumerate with
  `CGGetOnlineDisplayList`: a mirrored Sidecar is not in the active list.
- Print each transition to stdout (`logs/vdisp.out.log`), one line:
  `keep-awake on (sidecar display N)` / `keep-awake off (no sidecar display)`.
- Toggle with env `VDISP_KEEP_AWAKE` (default `1`; `0` disables). Add
  `<key>VDISP_KEEP_AWAKE</key><string>1</string>` to the template's
  `EnvironmentVariables`. The switch exists so that test T2 in `UC-DROPS.md` (A/B on
  `GlueIdleTimeout`) can be run with it off.
- The assertion is released automatically when the process exits; no extra cleanup is
  needed (see B6 for SIGTERM).

**Do not** use `caffeinate` from `bin/sidecar`: it would die with the shell or need its own
supervision. **Do not** change `pmset` settings: they are system-wide and need sudo.

**Accept.**
- With Sidecar connected: `pmset -g assertions` lists a `PreventUserIdleDisplaySleep` owned
  by `vdisp`.
- After `sidecar down`: it is gone within 30 s.
- `VDISP_KEEP_AWAKE=0`: never taken.

**Verify offline.** `./build.sh`. Run a second instance by hand with
`VDISP_KEEP_AWAKE=1 VDISP_WIDTH=640 VDISP_HEIGHT=480 bin/vdisp` while the session is up,
check `pmset -g assertions`, then stop it with **SIGTERM** (never `kill -9`). Do not restart
the LaunchAgent yet: that belongs to the live phase.

### A2. `up` is idempotent

**Why.** RC2a: 26 of 37 afternoon drops on 11-02 followed a tool connect/disconnect.
Today `cmd_up` always runs `disconnect_quiet` + `connect_with_retries`
(`tools/bin/sidecar` `cmd_up`, lines ~463–526), even on a healthy session.

**Change** in `cmd_up`, after `cmd_ensure` and the stale-display check:
- `healthy` means all of:
  1. `sidecar_probe_state` is `connected`;
  2. a Sidecar display is online (`sidecar_connected`);
  3. there is no `state/resolution`, **or** `current_sidecar_mode` equals it.
- If `healthy` and no `--force`:
  - `info "session healthy (id=…, WxH): no reconnect"`;
  - skip straight to the layout step (mirror or arrange, both idempotent after B2/B3);
  - return 0.
- `--force` keeps today's behaviour (disconnect, pass 1, optional pass 2). Update `main()`
  so `up` accepts `--force` (today only `res` takes an argument), and update `usage_up`
  and the README.

**Accept.** Two `sidecar up` in a row: the second prints `session healthy` and logs no
`connect "` / `disconnect "` line; the recorder shows no `TOOL CONNECT` and no `UC DROP`
for it.

### A3. No reconnect storms

**Why.** 11-02 14:18, 19:10, 19:27, 19:35, 19:48: dozens of `connect → CONNECTED → CLOSED`
per minute from earlier versions. The current loop (`connect_with_retries`, lines
~407–461) can still reconnect after "connect returned ok but the Sidecar display did not
appear".

**Change.**
- After a `connect` with exit 0 and no display after `CONNECT_SETTLE`:
  - if `sidecar_probe_state` is `connected`, **do not reconnect**: poll for the display up
    to 10 more seconds;
  - if it is `disconnected` (the session closed right after connecting), count a *flap*.
- Two flaps in one `up` → stop with:
  `fail "the session closed right after connecting twice: likely a stale display or the
  iPad held by another Mac; run sidecar doctor"`.
- Keep the existing classification for non-zero exits.

**Accept.** By reading the code, plus a bash unit test that stubs `SidecarLauncher` and
`connected` with scripts in a temp `BIN` dir (see "Offline test harness").

### A4. Timeouts and the "device not found" exit

**Why.** `SidecarLauncher/main.swift` waits on `dispatchGroup.wait()` with no limit: a lost
completion hangs `up` forever. Exit 3 ("not in the list of available devices") is treated
as fatal, yet it is transient when the iPad is not announced yet.

**Change** in `tools/bin/sidecar` only (leave `SidecarLauncher/main.swift` upstream-
compatible):
- Add `run_with_timeout SECONDS cmd…`: run in background with output to a temp file, a
  watchdog `sleep SECONDS; kill -TERM pid`, `wait`, return the command's rc or `124` on
  timeout. Bash 3.2 compatible, no `timeout(1)` (absent on macOS).
- Use it for `connect` (`CONNECT_TIMEOUT=30`) and `disconnect` (`DISCONNECT_TIMEOUT=15`).
- `classify_connect`: `rc 124` → `retry` with `connect timed out after Ns`; `rc 3` →
  `retry`.
- Keep the log line `connect "<NAME>" exit <rc>: …` format.

**Accept.** Stub harness: a fake `SidecarLauncher` that sleeps 60 → `up` gives up after
`CONNECT_ATTEMPTS × 30 s` with clear messages; a fake that exits 3 twice then 0 → connected
at attempt 3.

---

## Phase B — correctness from the review

### B1. One rule to pick the displays, everywhere

**Why.** The online list (needed for a mirrored Sidecar) also contains orphans.
`arrange.swift:35` takes the *first* Sidecar and `:41` the *largest* virtual display. With
an orphan or two virtual displays of the same size, the choice is arbitrary.

**Rule**, duplicated as a small function in each helper (each helper is compiled on its
own; keep it under 20 lines):
- **Sidecar**: online, vendor `0x6161706c`; prefer `CGDisplayIsActive != 0 ||
  CGDisplayMirrorsDisplay != 0`; among those the highest id (newest session).
- **Virtual**: online, vendor `0x5644`; prefer `CGDisplayIsMain != 0`, then active, then the
  largest.

**Files:**
- `tools/src/arrange.swift`;
- `tools/src/setmode.swift` and `tools/src/dispmode.swift` (both still on
  `CGGetActiveDisplayList`; verified: `dispmode` lists only display 17 while Sidecar 22
  mirrors it);
- `tools/src/mirror.swift` (also on the active list).

**Accept.**
- `bin/dispmode` lists the Sidecar display while it is mirrored.
- `bin/setmode 1321x918` finds it.
- `sidecar res` shows its modes.

### B2. `mirror` reports failure and is idempotent

**File** `tools/src/mirror.swift`.
- Use the B1 rule and drop `0x756e6b6e` (headless framebuffer) from `isSidecar`.
- If `CGDisplayMirrorsDisplay(sidecar) == builtin`, print
  `already mirrored: sidecar N -> builtin M` and exit 0.
- Exit 1 when `CGConfigureDisplayMirrorOfDisplay` or `CGCompleteDisplayConfiguration` is not
  `.success` (today it always exits 0, so `up` prints "mirror applied" on failure).

### B3. `arrange` reports an unclean result

**File** `tools/src/arrange.swift`, the end of phase 4 (line ~128). Exit **3** for "applied
but the check is not clean". In `cmd_up`:
- rc 3 → `warn "arrange applied but not verified (see logs/arrange.log)"`;
- other non-zero → today's warning;
- 0 → today's info.

### B4. `dispid` exposes mirroring; `doctor` and `status` use it

**Why.** `doctor` (lines ~776–788) decides "Sidecar mirrors it" with `mirror_state`, which
parses localized `system_profiler` output. That is slow (~1–2 s), language-dependent, and
only says that the Sidecar mirrors *something*. `display_line "vendor=$VENDOR_VDISP"` has no
end anchor and, with zombie virtual displays, takes the first line, not the main one.

**Change.**
- `tools/src/dispid.swift`: add `active=<bool> mirror_of=<id>` **before** the resolution.
  `resolution()` in `bin/sidecar` reads the **last** field, so the resolution must stay
  last. New line:
  `id=… vendor=… model=… serial=… builtin=… main=… active=… mirror_of=… WxH`.
- `bin/sidecar`: add `virtual_line` (the line for vendor `0x5644` with `main=true`, falling
  back to the first) and `sidecar_line` (the Sidecar line with `active=true` or
  `mirror_of≠0`, falling back to the first). Anchor vendors with `([[:space:]]|$)`.
- `doctor`, lid closed: OK iff the virtual line has `main=true` **and** the Sidecar line has
  `mirror_of=<virtual id>`. Print both ids in the message. Remove the unused `sline` local.
- `status`: print the mirror as `mirror: sidecar 22 -> 17` from `dispid`. Keep
  `mirror_state` only as a fallback, or delete it if nothing else uses it.

**Accept.** On the current state (virtual 17 main, Sidecar 22 `mirror_of=17`), `doctor` is
`consistent` and runs without `system_profiler`: `time sidecar doctor` is well under 1 s.

### B5. `res` explains a mirrored Sidecar

**Why.** While the Sidecar mirrors the virtual display, its own mode does not change what
the iPad shows (the iPad shows the virtual display, sized by `VDISP_WIDTH/HEIGHT`).

**Change.** `res_show` and `cmd_res`: if the Sidecar line has `mirror_of≠0`, print
`note: Sidecar mirrors display N; the iPad shows display N (VDISP_WIDTH/HEIGHT in the
LaunchAgent template), not this mode.` Still allow `res WxH` (it is remembered for the next
session).

### B6. `vdisp` handles SIGTERM explicitly

**Why.** The README rule "SIGTERM releases the display, SIGKILL does not" cannot be
explained by the code: `vdisp` installs no handler, so the two signals are identical to the
process. The observed difference is probably timing (KeepAlive recreating the display before
the old one is gone).

**Change.**
- `vdisp.swift`: `signal(SIGTERM, SIG_IGN)` and `signal(SIGINT, SIG_IGN)`, then
  `DispatchSource.makeSignalSource` for both. On fire:
  1. release the A1 assertion;
  2. drop the display reference (keep it in a `var display: NSObject?` and set it to `nil`);
  3. wait 0.5 s on the main queue;
  4. `exit(0)`.
- Template: add `<key>ThrottleInterval</key><integer>10</integer>` so that KeepAlive does not
  recreate the display before the WindowServer has released the old one.

**Accept** (live phase only: it breaks the current session). `sidecar restart-vdisp` leaves
exactly one `0x5644` display in `bin/dispid`, and `vdisp.out.log` shows the shutdown line.

### B7. README

`tools/README.md`:
- "Verifying" example: Sidecar is no longer `main`; show `mirror: sidecar N -> virtual M`.
- Remove or qualify the "~1 min vs ~4 min" Universal Control figure: it was measured with
  `up`/`down` and a `vdisp` restart inside the window. Link `UC-DROPS.md` instead.
- Document A1 (`VDISP_KEEP_AWAKE`), A2 (`up --force`), A4 (timeouts), B4 (new `dispid`
  fields).
- Known limits: "every switch of the iPad between Macs costs one UC drop per transition (OS
  behaviour)".

---

## Phase C — visibility of the factors we cannot control

### C1. `status` and `doctor` show the UC defaults and who keeps the display awake

Read-only; no defaults are written by the tools (whether to keep `GlueIdleTimeout` is the
user's decision, pending test T2).

- `status`:
  - `uc defaults: GlueIdleTimeout=3600 AutomaticallyReconnect=1` from
    `defaults read com.apple.universalcontrol <key> 2>/dev/null`, or `unset`;
  - `display awake: vdisp, UniversalControl`, the owners of `PreventUserIdleDisplaySleep`
    parsed from `pmset -g assertions`.
- `doctor`: an `info` line with the same two facts. `FAIL` only if a Sidecar display exists,
  A1 is enabled, and `vdisp` does not hold the assertion.

---

## Offline test harness (for A2–A4)

Create `tools/tests/` (new, so nothing existing changes) with a script that:
1. makes a temp dir with stub executables `SidecarLauncher`, `connected`, `dispid`,
   `vdisp`, `arrange`, `mirror`, `setmode`, `dispmode`, driven by env vars (exit code,
   output, sleep, "display appears after N calls");
2. runs `bin/sidecar` with `BIN` pointing at the stubs. Today `BIN` is derived from the
   script path: add an override, `SIDECAR_BIN="${SIDECAR_BIN:-…}"`, used only by tests;
3. checks the outcomes of these cases:
   - healthy session → no connect;
   - `--force` → one disconnect + one connect;
   - flap twice → abort;
   - timeout → retry, then give up;
   - exit 3 → retry;
   - `-501` → immediate abort;
   - arrange rc 3 → WARN.

Run it with `bash tools/tests/run.sh`; it must not touch the real displays or `logs/`
(point `TOOLS`/`LOGS` at the temp dir too).

---

## Live verification (at the end, with the user present)

Order chosen to minimise reconnects. The recorder is running; read it with
`~/sidecar-watch/bin/uc-analyze --verbose`.

1. `./build.sh`, then `./install.sh` (restarts vdisp with A1 and B6 → **ends the current
   session**: expect one UC drop).
2. `sidecar up` → one connect (session was gone). `pmset -g assertions` shows `vdisp`
   holding `PreventUserIdleDisplaySleep`.
3. `sidecar up` again → `session healthy`, **no** connect, **no** UC drop in the recorder.
4. `sidecar doctor` → `consistent`, under 1 s; `sidecar status` shows mirror, UC defaults,
   display-awake owners.
5. `sidecar res` → lists the Sidecar's modes and the mirroring note.
6. `bin/dispmode`, `bin/dispid` → the Sidecar appears, with `mirror_of`.
7. Only if the user agrees: `sidecar restart-vdisp` → exactly one `0x5644` display
   afterwards (B6).

Expected cost: 2 UC drops (steps 1–2), plus 1–2 for step 7. Report each with its recorder
line.

## Not in scope

- Changing UC defaults (`GlueIdleTimeout`, `AutomaticallyReconnect`): user decision, after
  test T2 in `UC-DROPS.md`.
- Changing the layout: test T5, last.
- Moving the recorder into `tools/`: after it has proved useful, as a separate change.
- `SidecarLauncher/main.swift` (upstream code): unchanged; timeouts live in the wrapper.
