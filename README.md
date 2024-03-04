# SidecarLauncher
A commandline tool to connect to a Sidecar capable device. No AppleScript, yay 🥳

List reachable Sidecar capable devices:

`./SidecarLauncher devices`

Connect to the device:

`./SidecarLauncher connect "My iPad"`

Disconnect from device:

`./SidecarLauncher disconnect "My iPad"`

Initially validated on Mac OS 14.2.1. Subject to break on macOS updates due to use of private APIs.

Use [this convenient shorcut](https://github.com/Ocasio-J/SidecarLauncher/raw/main/Sidecar%20Launcher.shortcut) to trigger Sidecar from an iPad.
See comments in the shortcut for some important notes.
