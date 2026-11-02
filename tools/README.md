# sidecar — a virtual display so Sidecar survives a closed lid

## Rules that keep this working

> **Never `SIGKILL` `vdisp`, and do not restart it with `launchctl kickstart -k` or
> `launchctl bootout`.** Both leave the display behind as an orphan in the WindowServer.
> Use `kill -TERM <pid>` (or `sidecar restart-vdisp`): the process releases its display
> on the way out, and `KeepAlive` starts it again with a fresh identity.
>
> `SIGTERM` releases the display; `SIGKILL`, `kickstart -k` and `bootout` do not.

Once a display is orphaned, no process owns it any more: only a WindowServer
re-enumeration (**open and close the lid once**) removes it. `kill`, `bootout` and
`CGConfigureDisplayEnabled` cannot. See [Troubleshooting](#troubleshooting).

## What it does

```
sidecar up             → virtual display + connect + saved resolution + arrange + mirror
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

Display origins decide what you see on the iPad. The virtual display is created **before**
the connect, so it gets origin `(0,0)` and becomes the **main** display; the Sidecar
display then arrives as a secondary screen to its right. With the lid closed that means
the iPad shows an empty extended desktop, which looks exactly like "the resolution is
wrong".

`bin/arrange` fixes the geometry with public API: Sidecar to `(0,0)` and every other
display **stacked below it**, each new row starting at `y + height` of the previous one
(`CGDisplayPixelsHigh`). `up` calls it automatically when the lid is closed (no built-in
display), **after** the final connect and before the mirror. When a built-in display
exists, `arrange` is not called: the physical panel stays main and Sidecar is extended or
mirrored as before.

**Why below, and why small.** With the lid closed and Universal Control, the pointer
enters the Mac from the edge of another screen. If the virtual display sat to the *right*
of Sidecar, every horizontal entry would land on an invisible 2642-pixel-wide rectangle and
the cursor would disappear. Stacking the others *under* Sidecar means a horizontal entry
lands on the iPad, and the only way to reach the placeholder is to go looking for it
vertically.

The virtual display itself is now **640x480** (`VDISP_WIDTH` / `VDISP_HEIGHT` override the
default). Its resolution is irrelevant: `DesktopMode` only checks that a non-built-in
display is active, nothing is ever drawn on it, and a small rectangle leaves little room to
lose the pointer in. To override it, export the variables before starting `vdisp` by hand,
or add them under `EnvironmentVariables` in the plist.

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

Because `install.sh` boots the agent out, and `bootout` does not release a running
display, run `./bin/sidecar doctor` afterwards: if it reports a zombie `0x5644` display,
open and close the lid once. Re-run `install.sh` after moving the folder or rebuilding.

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

Without the agent, `sidecar ensure` (and therefore `up`) starts `vdisp` in the background
itself, logging to `logs/vdisp.log`; it survives the shell, not a reboot.

## Usage

```
sidecar ensure      # start vdisp if needed, wait up to 10 s for vendor 0x5644
sidecar up          # ensure, disconnect, connect, [setmode, reconnect], arrange/mirror
sidecar down        # disconnect, wait up to 5 s for the Sidecar display to go away
sidecar status      # lid, vdisp, Sidecar display (id, resolution), mirror
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
   until vendor `0x5644` appears (10 s budget).
2. `disconnect "iPad"`, errors ignored: it clears zombie sessions that hold the iPad.
3. **pass 1** — `connect`, retried or aborted as in the table below. An attempt counts as
   successful only with exit 0 **and** vendor `0x6161706c` in `dispid` 3 s later.
4. if `state/resolution` exists: `setmode` to that mode.
5. **pass 2** — `disconnect` and `connect` again, so the new session starts with that
   mode. macOS remembers the mode per display, but a change made on a live session is
   only reliably applied at the next connection.
6. verify the current mode against `state/resolution`; a mismatch is a **warning**, not a
   failure.
7. with the lid closed: `arrange`, so Sidecar is at `(0,0)` and the others are stacked
   below it.
8. with a built-in display: `mirror` onto it.

Without `state/resolution` there is a single connect and no second pass.

| outcome of `connect` | behaviour |
|---|---|
| exit 0 and the display appears | connected, continue |
| exit 0 but no display after 3 s | retry (not an error, just not there yet) |
| `-455 SidecarErrorDisplayAWDLDegraded` | retry (transient, verified); if every attempt fails, see [Troubleshooting](#-455-sidecarerrordisplayawdldegraded-persistent) |
| `-101 SidecarErrorServiceDisconnected` | retry (transient, verified) |
| `-203 SidecarErrorDeviceWiFiNotEnabled` | retry (iPad asleep: it wakes and passes) |
| exit 2 / `No sidecar capable devices detected` | retry (iPad not announced yet) |
| `-501 SidecarErrorVirtualDisplayFailed` | **abort**, with the lid-cycle message |
| anything else | **abort** |

Retrying a fatal error is what multiplied the orphan displays: five attempts on `-501`
gave five zombies.

Exit codes: `0` success, `1` failure (`status`: `1` = not connected). Every message is
logged with an ISO timestamp to `logs/sidecar.log`; stdout stays to one line per step.

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

`up` closes the loop itself, but only when there is something to close. After the first
connect it compares the mode macOS negotiated with the saved one:

- **equal** — nothing to inherit: `mode 1321x918 already negotiated by macOS: no reconnect
  needed`, one connect only;
- **different** — `setmode` to the saved mode, then a second connect so the new session
  starts with it, then a check.

The second pass is deliberately conditional: every `connect` creates a new Sidecar display
id, and Universal Control on the other Macs keeps a tile per id, so reconnecting for
nothing litters the screen with duplicates.

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
orphans disappear. Then `sidecar up` again. `up` refuses to start while an orphaned
Sidecar display is listed (one with no connected device), instead of spending a connect on
it; `sidecar down` cannot remove it either, because nothing owns it.

**Why the obvious tools do not work.** An orphaned display is not owned by any process, so
`kill`, `pkill`, `launchctl bootout` and `CGConfigureDisplayEnabled` have nothing to act
on: they leave it exactly where it is. Only re-enumeration clears it.

**How not to get there.** Never `SIGKILL` `vdisp`, and never restart it with
`launchctl kickstart -k` (SIGKILL) or `launchctl bootout`: both were verified to leave the
display behind. Use `sidecar restart-vdisp`, which sends `SIGTERM` and waits for the old
display to go away and a new one to appear.

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
# vdisp:            alive (pid 77186)
# virtual display:  0x5644 up (640x480, id=34)
# sidecar:          connected (id=33, 1321x918, main)
# mirror:           no

./bin/sidecar doctor
# doctor: read-only consistency check
# ...
# result: consistent

./bin/dispid                      # raw display list
./bin/sidecar res                 # current mode + HiDPI list
/usr/bin/log show --last 3m --style compact | grep -E 'DesktopMode|3072'
```

`log` is a zsh builtin: call `/usr/bin/log` explicitly.

`doctor` compares displays against processes, Sidecar against
`SidecarDisplayManager.connectedDevices` (via `bin/connected`), checks that the virtual
display exists, and — with the lid closed — that Sidecar is the main display. It exits 1
and prints a `fix:` line for every problem.

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
| the virtual display dies with its process | but only if the process exits cleanly: see the rules at the top |
| the placeholder is still a display | 640x480 under Sidecar, but Universal Control can reach it by moving vertically; it is small so the pointer is easy to bring back |
| the mode is chosen by Sidecar | every `connect` negotiates its own mode, which is why `state/resolution` exists and `up` reapplies it — with a second connect only when the negotiated mode differs |
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
logs/                                  sidecar.log, vdisp.log, arrange.log, mirror.log (git-ignored)
state/                                 state/resolution (git-ignored)
```
