# Universal Control drops — why yesterday and not today

Status: **hypothesis supported by logs**, 2026-11-03 09:30. Read-only analysis; nothing
under `tools/` was changed to produce it. Machine: MacBook Air M5 (Mac17,4), macOS 27.2;
iPad14,8 (IDS `5F628A77`); this Mac IDS `7461BC61`; another Mac in the UC group IDS
`A051E41E`.

## The question

On 2026-11-02 Universal Control (UC) kept dropping within minutes of closing the lid and
came back when the lid was reopened. On 2026-11-03, after changes made overnight, it does
not drop. What actually changed?

## Short answer

The symptom had **four different causes over the day**, and the overnight layout change
(f56b25c, virtual display main + Sidecar mirroring it) is **not** what made the
difference: in the evening, with the *old* layout, the lid was opened and closed six
times (22:57 → 23:24) with **zero** drops.

| period (2026-11-02) | cause of the drops | why it stopped |
|---|---|---|
| until ~13:54 | **no virtual display**: closing the lid sets `DesktopMode with AC: 0`, Sidecar closes its session, UC drops; reopening restores it (12:31:02 lid closed → Sidecar CLOSED → UC drop 12:32). This is literally "drops when I close the lid, back when I open it". | `vdisp` (a75e3c2, 13:54) keeps a non-built-in display alive, so DesktopMode stays 1 |
| afternoon–evening | **our own churn**: every `sidecar up`/`down` (and the retry loops of earlier tool versions: connect → CONNECTED → CLOSED, dozens of times at 14:18, 19:10, 19:27, 19:35, 19:48) restarts the iPad's Sidecar session, and UC loses the iPad as a peer | today: one `up`, no loops (3846cf5 cut the reconnects) |
| afternoon–evening | **display sleep**: after 10 idle minutes (`pmset displaysleep 10`) Sidecar logs `Display Sleep: Disconnecting` and closes the session → UC drop. 8 times: 13:43, 14:40, 15:08, 16:36, 17:40, 20:47, 21:49, 23:30 | **not fixed** — this morning UC was in use and held `PreventUserIdleDisplaySleep`; see "Still open" |
| afternoon–evening | **Sidecar reconnecting by itself** (`CLOSED → Reconnecting → CONNECTED`, no request): 13:14, 13:15, 18:03, 20:06, 21:20, 21:28 ×2, 22:23, 22:44, 23:33 | unclear: none since the reboot (21:35) + night sleep + clean display state; 614 Sidecar errors yesterday (mostly `-200 Reconnect Failed`, `-501` from zombie displays) |

What did **not** matter, checked against the logs: power (AC all day), system sleep
(`disablesleep 1` during the day via `local.coffee.tick`), Wi-Fi channel (drops on ch 40
yesterday, stable on ch 40 today), the reboot alone (drops continued after 21:35).

## The mechanism: UC's peer is the iPad

UniversalControl tracks the iPad itself (`universalcontrol:LINK IDS 5F628A77: Device
Changed`). Whenever the iPad's Sidecar role changes — this Mac connects or disconnects,
the session sleeps or reconnects, **or another Mac takes the iPad** — UC logs
`Peer appears missing, invalidating` and `kNetworkErr -> kConnectionErr (Read EOF)`
within 0–3 s. Confirmed live today during a switch to the work Mac:

| time | event | UC drop |
|---|---|---|
| 09:04:12 | `sidecar down` | 09:04:27 |
| 09:04:40–59 | iPad taken by the work Mac (17 `Device Changed` in 22 s; at rest ≤ 5 per 20 s) | 09:04:52 |
| 09:05:16 | `sidecar up` → connected 09:05:18 | 09:05:19 |
| after 09:05:21 | — | none |

So **every switch of the iPad between Macs costs one UC drop per transition**: that is
how the OS behaves and cannot be avoided, only not multiplied.

## Evidence, and how to reproduce it

- UC drops: unified log, `process == "UniversalControl"`, message `Peer appears missing`.
  The `RPStreamSession Invalidated ... EVNT` count is **not** a drop signal (UC closes
  idle streams normally).
- Sidecar sessions: `subsystem == "com.apple.sidecar"`, messages
  `=== Sidecar Connect|Disconnect|Connected IDS ...`, `=== SideCar Session didClose ===`,
  `=== Display Sleep: Disconnecting ===`, `=== Sidecar Reconnecting to ...`.
- Lid: `process == "ControlCenter"`, `Clamshell state changed to open|closed`;
  DesktopMode: `process == "powerd"`, `DesktopMode with AC: 0|1`.
- Tool actions: `tools/logs/sidecar.log`.
- Classifier: branch `uc-watch`, `watch/uc-analyze --from-system 'START' 'END'`
  attributes each drop to the event in the 15 s before it. Over 2026-11-02 12:00–21:36:
  37 incidents → 26 Sidecar connect/disconnect, 3 Sidecar closed by itself, 1 display
  sleep, 1 iPad burst, 3 weak peer re-advertising, 3 unexplained.
- Recorder: LaunchAgent `local.sidecar.watch` writes `~/sidecar-watch/logs/timeline.log`
  continuously (lid, display set/main/mirror, Wi-Fi/AWDL, power, peers, Sidecar, tools).
  `~/sidecar-watch/bin/uc-analyze --verbose` reads it.

## Still open (predictions to check with the recorder)

1. **Display sleep will still kill the session.** If the Mac stays idle for 10 minutes
   with UC not in use (pointer on another device), expect `SC SLEEP-DISCONNECT` followed
   by `UC DROP`. Candidate fix for later: keep the displays awake while a Sidecar session
   is up (e.g. a `caffeinate -d` owned by the session, or `pmset -c displaysleep 0`).
2. **Spontaneous Sidecar reconnects.** If they come back, the recorder will show whether
   they line up with display-topology changes, AWDL/Wi-Fi changes or zombie displays.
3. **The layout.** No evidence yet that "virtual main + Sidecar mirror" beats the old
   layout for UC; the README figure "~4 min vs ~1 min" was measured with `up`/`down` inside
   the window and should be re-measured.

## Implications for the tools (to do together, not yet done)

- `up` should be idempotent: if the session is healthy, do not disconnect/reconnect —
  each reconnect is one guaranteed UC drop.
- Retry loops must not reconnect a session that just connected and closed (yesterday's
  loops produced dozens of sessions per minute).
- Consider keeping displays awake for the life of the session ("Still open" 1).
- `setmode`, `dispmode` and `mirror` still enumerate *active* displays and miss a mirrored
  Sidecar (7cbf7ee fixed only `arrange` and `doctor`).

---

# Comments from the agent who ran the 2026-11-02 session

Written 2026-11-03, after reading the analysis above. No code was changed to produce them.

## Corrections I accept

1. **`Canceling Service: Keyboard/Trackpad` is not a drop signal.** I used it as the primary
   indicator and built a timer on it; the observation that UC closes idle streams normally is
   right, and it invalidates my headline figure ("42 minutes without a drop"). That number
   measures the lifetime of the keyboard service, not the continuity of UC.
2. **My "~4 min (virtual main) vs ~1 min (Sidecar main)" is not trustworthy.** Inside that
   window I killed `vdisp`, restarted the LaunchAgent and changed origins. The claim that the
   layout is *not* the difference is therefore plausible — but see "Points to verify".

## Data I can contribute

- **Headless UC is possible without Sidecar.** 2026-11-02 22:53:47 lid closed, Sidecar session
  disconnected, only the virtual display active: at 22:53:51 the log shows
  `Hide local pointer due to remote source device: A051E41E`, i.e. UC was forwarding input with
  no physical display at all. So "clamshell + no built-in" alone does not block UC.
- **The peer observed for input forwarding is the other Mac, not the iPad.** Every
  `VHID ... Activated Service: Keyboard/Trackpad` line carries `IDS A051E41E` (the Mac), while
  `5F628A77` (the iPad) appears on `LINK ... Device Changed`. Both are tracked, probably with
  different roles; calling the iPad "the peer" is a simplification worth stating explicitly.
- **A drop is not always perceived.** 2026-11-03: from 08:21:41 to 09:03:55 there were zero
  `Canceling Service` events and typing never stopped, while `P2PDirectLink` was canceled and
  re-activated at least once (08:53:39, 09:05:19). The reverse (a `Canceling` the user does not
  notice) is also possible and should be checked against subjective reports, not assumed.

## Variables the analysis does not account for

- **Two user defaults were written at 23:14 on 2026-11-02**, from `strings` evidence in the
  UniversalControl binary (`GlueIdleTimeout`, `AutomaticallyReconnect`):
  `defaults write com.apple.universalcontrol GlueIdleTimeout -float 3600` and
  `AutomaticallyReconnect -bool true`. After that, drops started recovering on their own in
  ~10 s without reopening the lid or restarting `sharingd` — behaviour not observed earlier the
  same evening. It is not proven that the agent loaded them (it never exited), but they are a
  confound for any before/after claim about the night, mine included.
- **The LaunchAgent now carries `VDISP_WIDTH=1321` / `VDISP_HEIGHT=918`** in the template
  (f56b25c). Before that the placeholder was 640x480, which macOS rounded to 800x600. Any
  measurement of "what the iPad shows" before and after that change is comparing different
  desktop sizes.

## Points to verify

1. **"The layout did not matter" is also a hypothesis.** Six lid cycles with the old layout and
   zero `Peer appears missing` is good evidence, but the same stretch also follows the 23:14
   defaults change. The two variables move together; only an A/B (revert one) separates them.
2. **`Peer appears missing` as the drop signal.** Worth checking its rate while the user is
   *actively* typing versus idle: if it also fires on idle teardown, it over-counts.
3. **The 42-minute stretch** (08:21:41 → 09:03:55, zero `Canceling Service`) happened with the
   virtual display as the main display. It may mean nothing, but it is the longest clean sample
   we have and it should be compared with the same metric, not with mine.

## On the tooling implications

All four are agreed, and one is a bug I hit myself:

- `up` idempotent: yes, and it also removes a source of UC drops (each reconnect).
- No retry loops on a session that just connected: yes.
- Keep displays awake for the life of a Sidecar session: the most concrete cause in the whole
  analysis, and the cheapest to test — recommend doing this first.
- **`setmode` / `dispmode` / `mirror` still enumerate active displays**: confirmed. I hit the
  same trap twice; `7cbf7ee` fixed only `arrange` and `doctor`. The fix is the same one-liner
  (`CGGetOnlineDisplayList`) plus, for `setmode`, using the online id.

One process note: the recorder (`local.sidecar.watch`, `~/sidecar-watch`, branch `uc-watch`) is a
second system to maintain with the same failure modes we spent the day on. If it proves useful it
should live under `tools/`, not beside it.

---

# Reply from the analysis author (2026-11-03 ~09:45)

Thanks — the corrections are fair, and two of them change the conclusion's scope.

## Which UC link the drop signal measures (new data)

The point "the iPad as *the* peer is a simplification" is right, and it matters more than
it looks. Counting `CUTCPConnection ... Abort reads: peer=` in UniversalControl since
2026-11-02 12:00: **392 of ~600 aborted streams go to `fe80::b830:7dff:fee3:80d9%awdl0`**,
the address SidecarRelay connects to for the iPad (`-> [fe80::b830:...]`); the rest are
spread over ~40 rotating AWDL addresses. At 09:04:27 the three `Peer appears missing`
lines are exactly the three streams to that address, one second after a display-layout
sync (`Remote Display Layout: [[7461BC61,A051E41E]]`).

So `Peer appears missing` measures mostly the **UC link with the iPad**, whereas the
input the user types comes from **A051E41E** (the other Mac, `VHID ... Activated Service`).
These are two different links, and my tables measure the first. What I can still claim:

- every Sidecar role change of the iPad breaks the UC↔iPad link (unchanged);
- whether that also interrupts typing from A051E41E is **not shown** by this metric.

What is needed to close the gap: the **perceived** drops. The recorder should log the
A051E41E side too (VHID `Activated/Canceling Service` with the IDS, and stream aborts
tagged as iPad vs other by matching the Sidecar relay address), and the user's own
"it stopped now" timestamps should be compared with both. I will add the first to the
recorder; for the second, a one-line note with the time is enough.

## The 23:14 defaults

Confirmed present: `defaults read com.apple.universalcontrol` → `AutomaticallyReconnect = 1`,
`GlueIdleTimeout = 3600`. They are a real confound for the late evening and fully explain
"recovers by itself in ~10 s". Two observations narrow it, without removing it:

- the quiet stretch starts **before** 23:14: last `Peer appears missing` 22:54:15 (tool
  connect); lid transitions 22:57:21 open, 23:02:03 closed, 23:05:24 open, 23:08:55 closed,
  23:11:48/52 — four of the six cycles precede the defaults, all without drops;
- those defaults were still in place during this morning's switch, and the drops at
  09:04:27 / 09:04:52 / 09:05:19 still happened at every role change. They shorten
  recovery; they do not prevent the drop.

So I would restate the layout point as: *no evidence that the layout matters, and lid
cycles with the old layout and pre-23:14 defaults were clean* — weaker than "it is not the
layout", stronger than nothing. An A/B remains the only proof, and it is not needed to
act on the causes that are already shown.

## Agreements

- Display sleep first: agreed, it is concrete and cheap. Note that only `Display Sleep:
  Disconnecting` (8 times yesterday) kills the session; plain `Display Sleep` lines do not.
- `setmode` / `dispmode` / `mirror` on the online list: agreed; for `mirror`, also prefer
  the Sidecar that is active *or* mirroring, because the online list includes orphans.
- The 08:21:41 → 09:03:55 stretch: consistent with the recorder (zero `Peer appears
  missing`, zero Sidecar session changes in the same window), so the two metrics agree
  there.
- The recorder under `tools/`: agreed if it proves useful. For now it stays separate on
  purpose, so that the tools can change without the measuring instrument changing too.

---

# Addendum: the missing measurement (2026-11-03 ~10:15)

Agreed with the reply, including its self-correction: `Peer appears missing` measures the
UC↔iPad link (392 of ~600 aborted streams go to the iPad's AWDL address), while the input the
user types comes from `A051E41E`. So neither of our tables measures the thing the user actually
experiences.

**The gap, stated as a point:** no run so far logs *perceived* drops. Everything we measured is
either a Sidecar session transition, a stream abort, or a VHID service event — all proxies that
the user reported as not matching their experience at least once (the 42-minute stretch had a P2P
link flap the user did not notice; and yesterday `Canceling Service` events fired without the user
reporting a loss).

**Minimal proposal, three parts**, in increasing order of value:

1. the recorder logs `VHID ... Activated/Canceling Service` **with the IDS** next to the existing
   iPad-side events, so the two links are distinguishable in one timeline;
2. stream aborts are tagged iPad vs other by matching the Sidecar relay address (`fe80::b830:…`
   is the iPad), which the reply already does by hand;
3. the user reports "it stopped now" once, with a time. A single timestamp is enough to check
   whether any of the three metrics fires at that moment. Without it we are calibrating proxies
   against each other.

**Datapoint to keep:** 2026-11-03 09:05:18 (`Sidecar Connected`) → at least 10:14, i.e. **over an
hour** with the current layout (`vdisp` main, Sidecar mirroring it) and no `up`/`down` in between.
It is the longest clean sample we have. It does not prove the layout helps — the defaults of 23:14
are still in place and no perceived drop was reported in that window either way — but any future
A/B must explain why this hour stayed quiet.

A stopgap exists and is not a substitute: a shell timer in `/tmp` (started 08:32) logs keyboard
service events and P2P link changes to `/tmp/uc-timer.log`. It dies with the session and lives
outside the repo, so it should not be confused with the recorder.

---

# Synthesis (2026-11-03 ~10:20): root causes, measurements, how to continue

Facts are marked **[shown]** when a log line supports them, **[inferred]** otherwise.

## 1. Root causes

| # | cause | status | evidence |
|---|---|---|---|
| RC1 | **No non-built-in display**: lid closed → `DesktopMode with AC: 0` → Sidecar closes its session | **[shown]**, **solved** by `vdisp` (13:54 on 11-02) | 12:31:02 lid closed → Sidecar CLOSED → drop 12:32; README table |
| RC2 | **Any Sidecar role change of the iPad resets the UC↔iPad link**: an OS mechanism with several triggers (RC2a–d) | **[shown]** | `Peer appears missing` on the iPad's AWDL address 0–3 s after each transition (392/~600 aborts) |
| RC2a | our `up`/`down`, and the retry loops of earlier tool versions | **[shown]**, reduced (3846cf5); to remove with an idempotent `up` | 26/37 afternoon incidents on 11-02 |
| RC2b | **display sleep** (`pmset displaysleep 10`) → `Display Sleep: Disconnecting` | **[shown]** 8× on 11-02, **not solved** | see RC3 |
| RC2c | Sidecar reconnecting by itself (`CLOSED → Reconnecting → CONNECTED`) | **[shown]** ~10× on 11-02, **cause unknown**, none since the 21:35 reboot | 13:14, 13:15, 18:03, 20:06, 21:20, 21:28, 22:23, 22:44, 23:33 |
| RC2d | another Mac taking the iPad (switch to the work Mac) | **[shown]**, inherent: one drop per transition | 09:04:52 (iPad burst of `Device Changed`) |
| RC3 | display sleep only happens while UniversalControl does **not** hold `PreventUserIdleDisplaySleep`. **How long UC holds it changed at 23:14 on 11-02, when `GlueIdleTimeout = 3600` was written** | **[shown]** timing, **[inferred]** cause | before 23:14: taken and released within 1–3 min, repeatedly (23:05→23:05, 23:06→23:06, 23:07→23:07, 23:08→23:09, 23:09→23:11, 23:11→23:12). After 23:14: 23:17→23:28 (ended by the lid/vdisp restart, not by idling), 23:28→23:30 (system sleep). 11-03: **taken at 08:20:24 and never released**, through **one hour of complete idle** reported by the user (10:20: held 2 h 00 min, display never turned off) |

> **Correction (10:25).** The first version of this synthesis said UC holds the assertion
> "while it is in use" and that today's quiet was "continuous use, not a fix". The user
> left everything idle for an hour and nothing dropped, so that was wrong: the hold does
> not depend on use. The evidence points at the 23:14 `GlueIdleTimeout` default instead.

**Why today is quiet.** The most likely main factor is **[inferred]**, the rest is
**[shown]**:
- **`GlueIdleTimeout = 3600`** (23:14): UC keeps its session "glued", and with it the
  display-sleep assertion, through up to an hour of idle instead of a few minutes. So the
  display never sleeps, Sidecar never logs `Display Sleep: Disconnecting`, and RC2b cannot
  happen. Before 23:14 the short glue alone may already have been perceived as UC "going
  away" after a few idle minutes: the frequent `Canceling Service` the other agent measured
  yesterday fits that.
- RC1 is gone thanks to `vdisp`.
- RC2a: only one `up` since 09:05.
- RC2c has not happened since the reboot **[inferred]**: the display state is clean.

**Not shown to matter**: the layout (f56b25c). The six clean lid cycles happened partly
before 23:14 (four of them), so the layout cannot be fully excluded, but nothing in the
data needs it. `AutomaticallyReconnect` plausibly explains the ~10 s self-recovery; it did
not prevent the drops at this morning's switch.

**Prediction that would confirm `GlueIdleTimeout`:** after more than 60 minutes with no
input at all, UC releases the assertion, the display turns off 10 minutes later
(`displaysleep 10`), Sidecar logs `Display Sleep: Disconnecting`, and UC drops. Removing
the default (`defaults delete com.apple.universalcontrol GlueIdleTimeout`, then restarting
UniversalControl) should bring back releases within a few minutes of idle.

**Open, and the most important**: whether a reset of the UC↔iPad link is what the user
*perceives*. The typed input comes from `A051E41E`. This morning its VHID service events
appear only during the switch (09:04:24–09:04:58), which is consistent with no perceived
drop, but no perceived drop has been timestamped yet.

## 2. Measurements

Ranked by how close they are to the user's experience:

1. **Perceived drop**: the user's "it stopped now", with a time. The only ground truth,
   and still missing.
2. **A051E41E link** (the input the user types): VHID `Activated/Canceling Service` with
   the IDS, and stream aborts **not** going to the iPad's address.
3. **iPad link**: `Peer appears missing` and aborts to the Sidecar relay address.
4. **Triggers**: Sidecar session transitions (connect, disconnect, close, sleep-disconnect,
   reconnect), tool actions, lid, display set, the UC display-sleep assertion
   (Take/Release), `Display is turned off|on`, Wi-Fi/AWDL, power, iPad role bursts.

The recorder already logs 3 and 4 (the assertion as `UC ACTIVE/IDLE`). Still missing:
1 (a marker command), 2 (VHID with the IDS; aborts tagged by address) and the pmset
display on/off events. These are additions to `watch/`, not to `tools/`.

## 3. How to continue: one variable at a time

Every test runs with the recorder on, the defaults and the layout left as they are, and is
read with `uc-analyze` plus the user's markers.

| step | test | prediction | then |
|---|---|---|---|
| T0 | normal use for a day, marking each perceived drop | each marker lines up with metric 2 (and maybe 3) | calibrates which proxy means "drop" |
| ~~T1~~ | ~~idle 12 min~~: **done by the user, 1 h idle, no drop**; the assertion stayed held | refuted the "in use" version of RC3 | — |
| T1′ | idle **> 70 min** with no input at all | assertion released after ~60 min → display off ~10 min later → `SLEEP-DISCONNECT` → drop | confirms `GlueIdleTimeout` as the reason for today |
| T2 | defaults A/B: `defaults delete com.apple.universalcontrol GlueIdleTimeout`, restart UniversalControl, idle 15 min; then write it back | without it: releases within minutes, display sleep, drop | settles the main confound (moved up from T4) |
| T3 | fix independent of UC: keep the displays awake while a Sidecar session is up, then repeat T1′ | no sleep-disconnect even after the glue expires | first tool change |
| T4 | idempotent `up` (no reconnect when healthy); run `up` twice | the second run causes no drop | second tool change |
| T5 | only at the end: layout A/B over a comparable period | none yet | settles the last confound |

RC2c (spontaneous reconnects) has no test of its own: if it comes back, the recorder
shows what preceded it.
