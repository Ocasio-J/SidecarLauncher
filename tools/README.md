# sidecar — a virtual display so Sidecar survives a closed lid

Five commands for a MacBook used **closed, on AC, reached over SSH**, that must keep an
**iPad Sidecar** session alive when no external monitor is attached:

```
sidecar up       → virtual display + disconnect + connect "iPad" + saved resolution + mirror
sidecar down     → disconnect "iPad"
sidecar status   → what is actually happening (read-only)
sidecar res      → current mode and HiDPI modes; sidecar res 1165x809 sets and saves one
sidecar ensure   → only the virtual display
```

No `sudo`, no AppleScript, no configuration files: bash plus six small binaries built from
`src/`.

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

- **the vendor stays fixed** (`0x5644`), because `ensure`, `status` and `dispid` look for
  exactly that vendor;
- **the identity must be unique per process**. With `serialNum`, `productID` and
  `vendorID` all pinned to `0x5644`, `CGVirtualDisplay` refuses to create a second
  display: `initWithDescriptor:` returns `nil`, the binary exits 1, and the first
  instance keeps working. `src/vdisp.swift` derives `serialNum` and `productID` from the
  pid and the current second, so two processes started even one second apart never
  collide, and the failure message prints the identity it tried.

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
`dispmode`, `setmode`, plus `bin/SidecarLauncher` from `../SidecarLauncher/main.swift`,
prints one line per binary and a summary. It is idempotent: rebuilding replaces the
binaries atomically, so a `vdisp` that is currently running keeps its old inode.

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
`launchctl bootstrap gui/$(id -u)`, and prints the resulting state and pid. Run it again
after moving the folder or rebuilding — it replaces the previous copy.

The agent keeps the display alive: `RunAtLoad` starts it at login, `KeepAlive` restarts
it if it dies. Both matter — if `vdisp` disappears, the Sidecar session dies at the next
lid closing.

It is a **user** LaunchAgent bound to the Aqua session (`LimitLoadToSessionType`):
`CGVirtualDisplay` needs a window server, so a machine with no graphical login is not
enough, even with SSH access. Output goes to `logs/vdisp.out.log` and
`logs/vdisp.err.log`.

To remove it:

```bash
launchctl bootout gui/$(id -u)/local.sidecar.vdisp
```

Without the agent, `sidecar ensure` (and therefore `up`) starts `vdisp` in the background
itself, logging to `logs/vdisp.log`; it survives the shell, not a reboot.

## Usage

```
sidecar ensure      # start vdisp if needed, wait up to 10 s for vendor 0x5644
sidecar up          # ensure, disconnect, up to 5 connect attempts, saved resolution, mirror
sidecar down        # disconnect, wait up to 5 s for the Sidecar display to go away
sidecar status      # lid, vdisp, Sidecar display (id, resolution), mirror
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
3. up to **5** `connect` attempts, 5 s apart. A transient failure is normal:
   `-455 SidecarErrorDisplayAWDLDegraded` and `-101 SidecarErrorServiceDisconnected` both
   succeed on a retry.
4. an attempt counts as successful only with **exit 0 and vendor `0x6161706c` present in
   `dispid` 3 s later** — `connect` returning 0 is not proof that a display appeared.
5. the mode saved in `state/resolution`, if there is one, before the mirror, so the clone
   inherits the new mode instead of being reconfigured after it. A saved mode that no
   longer exists only produces a warning: the session stays up.
6. `bin/mirror` if a built-in display exists. With the lid closed there is none: the
   mirror is skipped, logged, and `up` still exits 0.

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
committed. Both forms **require a connected Sidecar display** and fail with a clear
message otherwise — there is nothing to configure before `up`.

`setmode` prefers the HiDPI variant when more than one mode matches, and `up` treats a
mode that no longer exists as a warning, not a failure. `state/resolution` is one line of
plain text, `WxH` in points (`1165x809` means 2330x1618 pixels on a 2× display); delete
the file to stop `up` from touching the mode.

One caveat, observed: the display list and `sidecar status` reflect the new mode
immediately, but the **picture on the iPad updates reliably only after the session is
re-established** (`sidecar down && sidecar up`). Treat `res` as "remember this", not as
"live preview".

## Verifying

```bash
./bin/sidecar status
# lid:              closed
# vdisp:            alive (pid 70935)
# virtual display:  0x5644 up (2642x1836, id=19)
# sidecar:          connected (id=22, 1165x809, main)
# mirror:           no

./bin/dispid                      # raw display list
./bin/sidecar res                 # current mode + HiDPI list
/usr/bin/log show --last 3m --style compact | grep -E 'DesktopMode|3072'
```

`log` is a zsh builtin: call `/usr/bin/log` explicitly.

## Known limits

| limit | detail |
|---|---|
| the iPad is exclusive | a Sidecar session belongs to one host. This tool cannot take it from another Mac: release it **from the host that owns it** (Control Center, or that host's `sidecar down`) and retry. Otherwise `connect` fails or connects nothing |
| the iPad must be awake and unlocked | even then `connect` can fail with `-203 SidecarErrorDeviceWiFiNotEnabled`; wake it and retry |
| several virtual displays can coexist | each instance has its own `product`/`serial`, so the agent's `vdisp` plus a manual one is legal: you get two `0x5644` displays with different identities. `ensure` starts nothing if one is already there, and `status` reports the first of each |
| the virtual display dies with its process | `vdisp` must stay alive; the LaunchAgent is the answer, a `kill` is not |
| the mode is chosen by Sidecar | every `connect` negotiates its own mode, which is why `state/resolution` exists and `up` reapplies it |
| no graphical session, no agent | `LimitLoadToSessionType Aqua` means the agent runs only inside a logged-in desktop session |
| private APIs | `CGVirtualDisplay` and `SidecarCore` are not public; a macOS update can break either |
| one model tested | MacBook Air M5, macOS 27.2. `DesktopMode` behaviour may differ elsewhere |

## Layout

```
src/*.swift                            helpers: virtual display, mirror, display id/modes, setmode
build.sh                               compiles src/ into bin/ (plus the upstream launcher)
install.sh                             renders the plist, validates it, loads the agent
bin/sidecar                            the command (bash, set -euo pipefail)
bin/.gitignore                         ignores build outputs, keeps bin/sidecar
daemon/local.sidecar.vdisp.plist.in    LaunchAgent template (@@TOOLS@@ → absolute path)
logs/                                  sidecar.log, vdisp.log, vdisp.{out,err}.log (git-ignored)
state/                                 state/resolution (git-ignored)
```
