# sidecar — a virtual display so Sidecar survives a closed lid

## Rules that keep this working

> **`SIGTERM` is safe; `SIGKILL` is not.** `bin/vdisp` installs a `SIGTERM`/`SIGINT`
> handler that releases the display before exiting, so `kill -TERM <pid>`,
> `sidecar restart-vdisp` and `launchctl bootout` (launchd stops the job with `SIGTERM`)
> leave no orphan behind. `install.sh` boots the agent out on every run for this reason.
>
> `SIGKILL` and `launchctl kickstart -k` (which sends `SIGKILL`) bypass the handler: the
> process dies without releasing anything, and its display stays in the WindowServer with
> no owner. Do not use them.

Once a display is orphaned, no process owns it any more: only a WindowServer
re-enumeration (**open and close the lid once**) removes it. At that point `kill` and
`bootout` have nothing left to release, and `CGConfigureDisplayEnabled` cannot help
either. See [Troubleshooting](#troubleshooting).

## What it does

```
sidecar up             → virtual display + reconnect only when not healthy + arrange + mirror
sidecar down           → disconnect "iPad"
sidecar status         → what is actually happening (read-only)
sidecar doctor         → consistency check with the fix for every problem (read-only)
sidecar restart-vdisp  → SIGTERM the virtual display and wait for a fresh one
sidecar res            → current mode and HiDPI modes; res 1165x809 sets and saves one
sidecar ensure         → only the virtual display
```

No `sudo`, no AppleScript, no configuration files: bash plus seven small binaries built
from `src/`.

## Why a virtual display is required

Sidecar connects only if the Mac has **at least one active display that is not the
built-in one**. With the lid closed and no external display there is none, and macOS
tears the session down. Observed on macOS 27.2 (MacBook Air M5), not taken on faith:

| condition | what happens |
|---|---|
| lid closed, no other display, `connect "iPad"` | the session drops after ~6 s; the log shows `NSCocoaErrorDomain 3072` and `DesktopMode with AC: 0` |
| lid closed, virtual display created with `CGVirtualDisplay` | the log switches to `DesktopMode set 1`, and the session survives the lid closing |
| the process that owns the virtual display exits | the session drops at the next lid close |

So the display is not a workaround for resolution: it is the **condition** the desktop
mode logic checks. It also means the display must be owned by something that stays alive
— `bin/vdisp`, normally kept up by the LaunchAgent.

Two consequences worth knowing:

- **the vendor stays fixed** (`0x5644`), because `ensure`, `status`, `doctor` and
  `dispid` look for exactly that vendor;
- **the identity must be unique per process**. With `serialNum`, `productID` and
  `vendorID` all pinned to `0x5644`, `CGVirtualDisplay` refuses to create a second
  display: `initWithDescriptor:` returns `nil`, the binary exits 1, and the first
  instance keeps working. `src/vdisp.swift` derives `serialNum` and `productID` from the
  pid and the current second, so two processes started even one second apart never
  collide.

### Who is the main display, and where the others go

Display origins decide what you see. The virtual display is created **before** the
connect, so it already sits at `(0,0)` and is the **main** display; the Sidecar display
then arrives as a second screen to its right. Left alone, the iPad shows an empty extended
desktop, which looks exactly like "the resolution is wrong".

`bin/arrange` turns that into the arrangement used on a closed lid: the **virtual display
stays main at `(0,0)`**, every other display is chained to its right, and the **Sidecar
mirrors the virtual display**. A minute-scale comparison between this arrangement and the
other one used to be quoted here; it is withdrawn because it came from a six-minute window
with other variables in it and cannot be attributed to the arrangement. What is measured
and attributable is A1: with `vdisp` holding its own assertion, a live Sidecar session kept
the display awake for **26 minutes** with no `Display Sleep: Disconnecting` in the log. The
arrangement does not stop Universal Control from dropping for other reasons — see
[`docs/uc-hardening/analysis.md`](../docs/uc-hardening/analysis.md).

A mirrored display cannot be configured, so `arrange` works in phases, each with its own
`CGBeginDisplayConfiguration`/commit and its return codes on stdout:

1. clear any mirror on the Sidecar (`kCGNullDirectDisplay`);
2. put the virtual display at `(0,0)` and the others to its right, adding widths;
3. mirror the Sidecar onto the virtual display;
4. verify: the virtual display is main, the Sidecar is in a mirror set.

Re-running it is safe: if the state is already the desired one it prints
`already arranged: virtual display N is main and Sidecar M mirrors it` and exits 0 without
touching the configuration. It enumerates the **online** display list, like `dispid`: a
mirrored display is not in the *active* list, and the Sidecar arrives mirrored when it
inherits the arrangement from the previous session — enumerating active displays would
make it invisible and the run would abort while the geometry is already correct.

`up` calls it only when the lid is closed (no built-in display),
after the final connect and before `bin/mirror`. With a built-in display `arrange` is not
called: the physical panel stays main and `bin/mirror` mirrors the Sidecar onto it.

### The size of the mirrored desktop

In this arrangement the iPad shows the **virtual** display, so its resolution is the size
of the desktop that appears there. 640x480, the binary default, is rounded by macOS to
800x600 and the desktop looks tiny; the LaunchAgent therefore sets `VDISP_WIDTH=1321` and
`VDISP_HEIGHT=918` under `EnvironmentVariables`.

Those values belong in `daemon/local.sidecar.vdisp.plist.in`, **not** in the installed
plist: `install.sh` regenerates the file from the template on every run, so hand edits to
`~/Library/LaunchAgents/local.sidecar.vdisp.plist` are lost. After changing them, re-run
`./install.sh` so `vdisp` is recreated with the new size.

The displays involved, as reported by `bin/dispid`:

| display | vendor | model |
|---|---|---|
| built-in panel | `0x610` | — |
| Sidecar (iPad) | `0x6161706c` (`"capl"`) | `0x69506164` |
| virtual, created by us | `0x5644` | derived per instance |
| headless fallback framebuffer | `0x756e6b6e` | — |

## Build

Requires `swiftc` (Xcode command line tools). Nothing else, and no `sudo`:

```bash
./build.sh
```

It compiles `src/<name>.swift` into `bin/<name>` for `vdisp`, `mirror`, `dispid`,
`dispmode`, `setmode`, `connected` and `arrange`, plus `bin/SidecarLauncher` from
`../SidecarLauncher/main.swift`, prints one line per binary and a summary. It is
idempotent: rebuilding replaces the binaries atomically, so a `vdisp` that is currently
running keeps its old inode.

**Binaries are not in git.** `bin/.gitignore` ignores everything but the entrypoint
script, so a fresh clone has sources, build and install scripts, and nothing else; the
first `./build.sh` produces what is missing.

`bin/SidecarLauncher` is the upstream tool (source in `../SidecarLauncher/main.swift`); it
uses private `SidecarCore` APIs and may break on a macOS update. The helpers talk to
`CGVirtualDisplay` and `CGDisplayMode` directly, also private on paper, stable in
practice on the version below.

## Install

```bash
./install.sh
```

It renders `daemon/local.sidecar.vdisp.plist.in`, replacing `@@TOOLS@@` with the absolute
path of this folder, writes `~/Library/LaunchAgents/local.sidecar.vdisp.plist`, validates
it with `plutil -lint`, then `launchctl bootout` (errors ignored) followed by
`launchctl bootstrap gui/$(id -u)`, and prints the resulting state and pid.

The template also carries the size of the virtual display (`VDISP_WIDTH` / `VDISP_HEIGHT`
under `EnvironmentVariables`, 1321x918). Because `install.sh` re-renders the plist every
time, that is the only place those values survive — see
[The size of the mirrored desktop](#the-size-of-the-mirrored-desktop).

Because `vdisp` releases its display in the `SIGTERM` handler, `install.sh`'s `bootout`
is a clean stop: it waits up to 10 s for the old pid to leave, then bootstraps the agent
again so the new process creates a fresh display. Run `./bin/sidecar doctor` afterwards to
confirm there is exactly one `0x5644` display for the new pid; a zombie that survives here
comes from an older build or a hard kill, and only the lid cycle removes it. Re-run
`install.sh` after moving the folder or rebuilding.

The agent keeps the display alive: `RunAtLoad` starts it at login, `KeepAlive` restarts it
if it dies. Both matter — if `vdisp` disappears, the Sidecar session dies at the next lid
closing. It is a **user** LaunchAgent bound to the Aqua session
(`LimitLoadToSessionType`): `CGVirtualDisplay` needs a window server, so a machine with no
graphical login is not enough, even with SSH access. Output goes to `logs/vdisp.out.log`
and `logs/vdisp.err.log`.

To remove it:

```bash
launchctl bootout gui/$(id -u)/local.sidecar.vdisp
```

`bootout` stops the job with `SIGTERM`, so the display is released with the process: this is
the clean way to remove it.

Without the agent, `sidecar ensure` (and therefore `up`) starts `vdisp` in the background
itself, logging to `logs/vdisp.log`; it survives the shell, not a reboot.

## Usage

```
sidecar ensure      # start vdisp if needed, wait up to 10 s for vendor 0x5644
sidecar up          # ensure; reconnect only when unhealthy (--force: always); arrange/mirror
sidecar down        # disconnect, wait up to 5 s for the Sidecar display to go away
sidecar status      # lid, vdisp, Sidecar display (id, resolution), mirror, UC defaults,
                    # who holds the display awake, newest keep-awake line
sidecar doctor      # every check, every problem with its fix
sidecar restart-vdisp
sidecar res         # current mode of the Sidecar display + available HiDPI modes
sidecar res 1165x809  # apply that mode, remember it in state/resolution
sidecar <cmd> --help
```

`NAME` overrides the device name (default `iPad`):

```bash
NAME="Roberto's iPad" sidecar up
```

What `up` really does:

1. `ensure` — if `pgrep` finds no `vdisp`, it starts one and polls `dispid` every 0.5 s
   until vendor `0x5644` appears (`VDISP_TIMEOUT`, 10 s).
2. **gate** — a live Sidecar display (`active=true` **or** `mirror_of≠0` in `dispid`) with
   the probe reporting `connected` **or** `unknown` is a healthy session: `up` runs the
   layout step and exits 0 **without** disconnecting, connecting or touching
   `state/resolution`, so a second `up` costs zero resets. When the probe is unavailable it
   warns and assumes the live display is the session.
3. **A5, only when the session is not healthy but something is still there** (a display
   listed, or the probe reporting `connected`): wake the display with
   `caffeinate -u -t 2`, then wait up to `WAKE_SETTLE` for Sidecar to come back by itself.
   A session that returns live is healthy and is not reconnected — this is what turns a
   session waiting for the display to wake into a recovery instead of a `-501`. A suspended
   display that survives the wake is disconnected and given `WAKE_SETTLE` to clear; if it
   does not clear, `up` aborts with the lid-cycle instruction instead of spending a connect
   on `-501`.
4. `disconnect "$NAME"`, errors ignored: it clears zombie sessions that hold the iPad
   (skipped when A5 already disconnected).
5. **pass 1** — `connect`, retried or aborted as in the table below. An attempt counts as
   successful only with exit 0 **and** vendor `0x6161706c` in `dispid` `CONNECT_SETTLE`
   (3 s) later.
6. if `state/resolution` exists, compare it with the mode macOS negotiated in pass 1.
7. only when they differ: `setmode` to the saved mode, then **pass 2** (`disconnect` and
   `connect` again) so the new session starts with it. macOS remembers the mode per
   display, but a change made on a live session is only reliably applied at the next
   connection. Every connect creates a new Sidecar display id and Universal Control on the
   other Macs keeps a tile per id, so nothing is reconnected when nothing changes.
8. verify the current mode against `state/resolution`; a mismatch is a **warning**, not a
   failure.
9. with the lid closed: `arrange`, so the virtual display is main at `(0,0)`, the others sit
   to its right and Sidecar mirrors the virtual display.
10. with a built-in display: `mirror` onto it.

`--force` skips the gate and A5: after a bare `caffeinate -u -t 2` (no waits, no abort) it
runs the full reconnect path, so the saved mode is reapplied even on a healthy session.
Without `state/resolution` there is a single connect and no second pass.

| outcome of `connect` | behaviour |
|---|---|
| exit 0 and the display appears | connected, continue |
| exit 0 but no display after 3 s | retry (not an error, just not there yet) |
| `-455 SidecarErrorDisplayAWDLDegraded` | retry (transient, verified); if every attempt fails, see [Troubleshooting](#-455-sidecarerrordisplayawdldegraded-persistent) |
| `-101 SidecarErrorServiceDisconnected` | retry (transient, verified) |
| `-203 SidecarErrorDeviceWiFiNotEnabled` | retry (iPad asleep: it wakes and passes) |
| exit 2 / `No sidecar capable devices detected` | retry (iPad not announced yet) |
| exit 3 / not in the list of available devices | retry (device not announced yet) |
| no exit after `CONNECT_TIMEOUT` | retry after `TIMEOUT_RETRY_DELAY`; first it probes: a session that reports `connected` just waits for the display instead of reconnecting |
| `-501 SidecarErrorVirtualDisplayFailed` | **abort**, with the lid-cycle message |
| anything else | **abort** |

Retrying a fatal error is what multiplied the orphan displays: five attempts on `-501`
gave five zombies.

Exit codes: `0` success, `1` failure (`status`: `1` = not connected). Every message is
logged with an ISO timestamp to `logs/sidecar.log`; stdout stays to one line per step.

### Variables and timeouts

Everything is an environment variable with a default; there is no configuration file.

| variable | default | what it bounds |
|---|---|---|
| `NAME` | `iPad` | the Sidecar device `connect`/`disconnect` address |
| `SIDECAR_BIN` | unset | **test-only**: a directory the helpers are resolved from instead of `bin/`; unset keeps the normal layout, a non-directory fails loudly with no fallback |
| `VDISP_KEEP_AWAKE` | `1` | read from the LaunchAgent (or the environment): `1` makes `vdisp` hold `PreventUserIdleDisplaySleep` while a session is live (A1), `0` disables it so the display sleeps with the session |
| `KEEP_AWAKE_MAX_HOLD` | `0` | optional ceiling in seconds on how long `vdisp` keeps that assertion; `0` means no ceiling |
| `CONNECT_TIMEOUT` | `30 s` | one `connect`; hitting it is retried |
| `CONNECT_ATTEMPTS` | `5` | connect attempts per pass |
| `CONNECT_SETTLE` | `3 s` | how long after `connect` exit 0 the display is given to appear (success needs both) |
| `CONNECT_DISPLAY_WAIT` | `25 s` | how long A5 waits for the display on a session that already reports `connected` |
| `WAKE_SETTLE` | `10 s` | how long A5 waits for the session to come back after `caffeinate -u -t 2`, and for a disconnected display to clear |
| `DISCONNECT_TIMEOUT` | `15 s` | one `disconnect` |
| `RETRY_DELAY` | `5 s` | pause between ordinary retries |
| `TIMEOUT_RETRY_DELAY` | `10 s` | pause after a `connect` that hit `CONNECT_TIMEOUT` |
| `VDISP_TIMEOUT` | `10 s` | `ensure` waiting for vendor `0x5644` to appear |
| `DOWN_TIMEOUT` | `5 s` | `down` waiting for the Sidecar display to disappear |
| `RESTART_TIMEOUT` | `30 s` | `restart-vdisp` waiting for the old display to go and a new one to appear |

`POLL_INTERVAL` (0.5 s) is the polling step used everywhere.

### Resolution

The iPad negotiates its own list of modes and picks one on every `connect`, so the
resolution you get afterwards is whatever Sidecar decided. `res` makes it explicit:

```bash
./bin/sidecar res                 # current mode + HiDPI modes, read-only
./bin/sidecar res 1165x809        # apply it, remember it
```

Without arguments it prints the current mode of the Sidecar display and the HiDPI modes
it offers, as reported by `bin/dispmode`; nothing changes. With `WxH` it calls
`bin/setmode WxH`, writes the value to `state/resolution` and reports the mode actually
committed. Both forms **require a connected Sidecar display**.

`state/resolution` is one line of plain text, `WxH` in points (`1165x809` means 2330x1618
pixels on a 2× display); delete the file to stop `up` from touching the mode. `setmode`
prefers the HiDPI variant when more than one mode matches.

When the Sidecar display mirrors another display, both forms print a note naming the
display the iPad actually shows — the virtual one: the mode of the Sidecar display is then
not what the iPad renders, and the mirrored desktop is sized by `VDISP_WIDTH`/`VDISP_HEIGHT`
(1321x918 in the template), not by `res`.

This is the *Sidecar* mode. The size of the mirrored desktop is a different knob: it is
the resolution of the **virtual** display, set in the LaunchAgent template — see
[The size of the mirrored desktop](#the-size-of-the-mirrored-desktop).

`up` closes the loop itself, and only when it reconnects. After the first connect it
compares the mode macOS negotiated with the saved one:

- **equal** — nothing to inherit: `mode 1321x918 already negotiated by macOS: no reconnect
  needed`, one connect only;
- **different** — `setmode` to the saved mode, then a second connect so the new session
  starts with it, then a check.

The second pass is deliberately conditional: every `connect` creates a new Sidecar display
id, and Universal Control on the other Macs keeps a tile per id, so reconnecting for
nothing litters the screen with duplicates.

A healthy session never reaches this code: the gate returns before the disconnect, so
`state/resolution` is **not** reapplied by an idempotent `up`. It is reapplied when `up`
actually reconnects, or with `sidecar up --force`.

**`res` on its own does not reconnect**: it applies and saves, but the picture on the iPad
updates reliably only at the next connection. After a bare `sidecar res 1165x809`, run
`sidecar up` (or `sidecar down && sidecar up`) to see it.

## Troubleshooting

### `-501 SidecarErrorVirtualDisplayFailed`

**Symptom.** `connect` fails immediately with `SidecarErrorDomain Code=-501`, `up` stops
at the first attempt, and `status` may still look fine.

**Cause.** Zombie virtual displays: a display with vendor `0x5644` that stayed registered
in the WindowServer after the process that created it was killed hard. Sidecar refuses to
create its own virtual display while the configuration is in that state.

**Cure.** Open and close the lid once. The WindowServer re-enumerates the displays and the
orphans disappear. Then `sidecar up` again. On a listed Sidecar display with no connected
session `up` does not spend a connect: after the wake it tries one disconnect, and if the
display survives that it stops with the lid-cycle message. `sidecar down` cannot remove an
orphan either, because nothing owns it.

**Why the obvious tools do not work.** An orphaned display is not owned by any process, so
`kill`, `pkill`, `launchctl bootout` and `CGConfigureDisplayEnabled` have nothing to act
on: they leave it exactly where it is. Only re-enumeration clears it.

**How not to get there.** Never `SIGKILL` `vdisp`, and never restart it with
`launchctl kickstart -k`, which is `SIGKILL`: they bypass the handler and leave the display
behind. `kill -TERM`, `sidecar restart-vdisp` and `launchctl bootout` are safe, because the
handler releases the display on the way out.

### `-455 SidecarErrorDisplayAWDLDegraded`, persistent

**Symptom.** Every attempt fails with `-455 SidecarErrorDisplayAWDLDegraded`, with strong
signal, and the iPad is listed by `bin/SidecarLauncher devices`. A single `-455` is normal
and is retried; this is the case where all five attempts fail.

**What the log says.** AWDL reaches the peer and opens a TCP connection to `…%awdl0`, then
the *peer closes it*: `Read EOF`, `kConnectionErr`, `-6753`. The iPad is refusing the
session; it is not a signal or channel problem.

**What fixed it.** Toggle **Wi-Fi and Bluetooth off and on, on the iPad**, turn off Low
Power Mode and check Handoff. After that the connection succeeded on the first attempt on
the very same channel that had failed minutes before.

**What does not help.** Changing channel: verified on 5 GHz channel 64 (DFS) and on
2.4 GHz channel 1, both failing for the same reason. DFS is a red herring. Moving to
2.4 GHz is not a shortcut either — see below.

**If toggles are not enough.** Reboot the iPad: the radio state is then rebuilt from
scratch.

**Context: why 5 GHz.** AWDL (Apple Wireless Direct Link) is the side channel Sidecar uses
to discover and set up the peer. It works best in 5 GHz because on 2.4 GHz it shares the
antenna with Bluetooth, which is also active for keyboard, trackpad and Handoff; the
coexistence adds exactly the kind of latency that makes AWDL look "degraded".

### "The iPad shows an empty desktop"

The virtual display was created first and became the main one. `sidecar up` fixes it with
`bin/arrange` whenever the lid is closed; run `bin/arrange` by hand if you need it without
reconnecting.

## Verifying

```bash
./bin/sidecar status
# lid:              closed
# vdisp:            alive (pid 53586)
# virtual display:  0x5644 up (1321x918, id=34)
# sidecar:          connected (id=35, 1321x918)
# mirror:           sidecar 35 -> 34
# uc defaults:      GlueIdleTimeout=3600 AutomaticallyReconnect=1
# display awake:    vdisp, UniversalControl
# keep-awake:       on (connected=1) (41s ago)

./bin/sidecar doctor
# doctor: read-only consistency check
# ...
# result: consistent

./bin/dispid                      # raw display list
./bin/sidecar res                 # current mode + HiDPI list
/usr/bin/log show --last 3m --style compact | grep -E 'DesktopMode|3072'
```

`log` is a zsh builtin: call `/usr/bin/log` explicitly.

Besides the display state, `status` prints the factors the tools do not control:

- `uc defaults:` — `GlueIdleTimeout` and `AutomaticallyReconnect` as read from
  `com.apple.universalcontrol`, or `unset` when a key is absent;
- `display awake:` — who currently holds `PreventUserIdleDisplaySleep`. `vdisp` (A1) and
  Universal Control each hold their own, so both names can appear, and a live session with
  no `vdisp` owner is what `doctor` fails on;
- `keep-awake:` — the newest keep-awake line from `logs/vdisp.out.log` and
  `logs/vdisp.log`, with its age, or `unknown` when there is no line or the newest is older
  than ~120 s. The line is written on transitions, so a steady session can legitimately
  read `unknown`.

A session whose display is asleep is reported as
`sidecar: suspended (display N asleep): waiting for display wake`.

`dispid` prints one line per display: `id`, `vendor`, `model`, `serial`, `builtin`, `main`,
`active`, `mirror_of`, `asleep` and `WxH`. A Sidecar display is **live** when
`active=true` **or** `mirror_of≠0` (a mirrored display is not in the *active* list), and
`asleep=true` is how a suspended session's display is recognised.

`doctor` compares displays against processes, Sidecar against
`SidecarDisplayManager.connectedDevices` (via `bin/connected`), checks that the virtual
display exists, and — with the lid closed — that the virtual display is main and the
Sidecar mirrors it, which is the arrangement `bin/arrange` applies. It also reports the UC
defaults, the assertion owners and the keep-awake line as `info`, and fails a live session
that A1 is enabled for but `vdisp` does not keep awake. It exits 1 and prints a `fix:` line
for every problem.

`status` takes "connected" from the same probe, not from the display list, because a
stale display can outlive the session. If the probe is unavailable (the private accessor
changed), `status` falls back to the display list, says so on the line
(`display list only, probe unavailable`) and prints a warning; `doctor` reports the same
limitation as `info`, not as a failure.

## Known limits

| limit | detail |
|---|---|
| the iPad is exclusive | a Sidecar session belongs to one host. This tool cannot take it from another Mac: release it **from the host that owns it** (Control Center, or that host's `sidecar down`) and retry |
| the iPad must be awake and unlocked | even then `connect` can fail with `-203 SidecarErrorDeviceWiFiNotEnabled`; wake it and retry |
| several virtual displays can coexist | each instance has its own `product`/`serial`. A second one without a process is a zombie: `doctor` reports it, the lid cycle removes it |
| the virtual display dies with its process | if the process exits cleanly it releases the display first, so it dies with its process; a hard kill leaves it orphaned: see the rules at the top |
| the mirrored desktop is the virtual display | the display the iPad shows in mirror is the **virtual** one: `1321x918` from the template is the desktop size the iPad renders, and the other displays sit to its right |
| Universal Control stays unstable with the lid closed | the arrangement makes a session last longer; it does not prevent UC from dropping. No duration is quoted here because none is attributable — see `docs/uc-hardening/analysis.md`; recovery is ~10 s when UC reconnects by itself |
| every role change of the iPad costs a UC reset | handing the iPad from one Mac to another (or back) tears the UC link down and rebuilds it: one reset per transition is OS behaviour the tool cannot avoid |
| the mode is chosen by Sidecar | every `connect` negotiates its own mode, which is why `state/resolution` exists. `up` reapplies it only when it actually reconnects (the negotiated mode differs) or with `up --force`; a healthy session is left alone |
| every connect is a new display | each `connect` produces a fresh Sidecar display id, and **Universal Control on other devices can accumulate duplicate tiles** for the displays it has seen. Fewer reconnects means fewer tiles; stale ones disappear with a logout or a restart of the device showing them |
| no graphical session, no agent | `LimitLoadToSessionType Aqua` means the agent runs only inside a logged-in desktop session |
| private APIs | `CGVirtualDisplay` and `SidecarCore` are not public; a macOS update can break either, and the probe in `bin/connected` exits 3 instead of crashing when an accessor disappears |
| one model tested | MacBook Air M5, macOS 27.2. `DesktopMode` behaviour may differ elsewhere |

## Layout

```
src/*.swift                            helpers: vdisp, mirror, dispid, dispmode, setmode,
                                       connected (probe), arrange (geometry)
build.sh                               compiles src/ into bin/ (plus the upstream launcher)
install.sh                             renders the plist, validates it, loads the agent
bin/sidecar                            the command (bash, set -euo pipefail)
bin/.gitignore                         ignores build outputs, keeps bin/sidecar
daemon/local.sidecar.vdisp.plist.in    LaunchAgent template (@@TOOLS@@ → absolute path)
logs/                                  sidecar.log, vdisp.log, vdisp.out.log, vdisp.err.log,
                                       arrange.log, mirror.log, setmode.log, perceived.log
                                       (git-ignored; perceived.log is the user's drop marker)
state/                                 state/resolution (git-ignored)
```
