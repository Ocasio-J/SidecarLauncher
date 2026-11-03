# Shortcuts for the sidecar CLI.
#
#   source ~/SidecarLauncher/tools/aliases.sh
#
# or add that line to ~/.zshrc. Nothing here changes the tool's behaviour: every
# shortcut is a thin wrapper over `sidecar`, so `sidecar up --help` still works.

_sidecar_bin() {
  if command -v sidecar >/dev/null 2>&1; then
    command sidecar "$@"
  else
    "$HOME/SidecarLauncher/tools/bin/sidecar" "$@"
  fi
}

# Daily commands, spelled out.
sidecar_status()  { _sidecar_bin status; }
sidecar_doctor()  { _sidecar_bin doctor; }
sidecar_up()      { _sidecar_bin up "$@"; }
sidecar_down()    { _sidecar_bin down; }

# Force a reconnect even when the session looks healthy (costs one UC reset).
sidecar_force()   { _sidecar_bin up --force; }

# Restart the virtual display only. Costs one UC reset: use with the lid open,
# or accept that the session drops and comes back on its own.
sidecar_restart() { _sidecar_bin restart-vdisp; }

# Anything not covered above: resolution, ensure, --help.
#   sidecar_cli res 1165x809
#   sidecar_cli --help
sidecar_cli()     { _sidecar_bin "$@"; }
