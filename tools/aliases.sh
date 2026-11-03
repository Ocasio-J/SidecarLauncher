# Shortcuts for the sidecar CLI.
#
#   source ~/SidecarLauncher/tools/aliases.sh
#
# or add that line to ~/.zshrc. Nothing here changes the tool's behaviour: every
# shortcut is a thin wrapper over `sidecar`, so `sc --help` still works.

_sidecar_bin() {
  if command -v sidecar >/dev/null 2>&1; then
    command sidecar "$@"
  else
    "$HOME/SidecarLauncher/tools/bin/sidecar" "$@"
  fi
}

# Full CLI: sc up, sc down, sc res 1165x809, sc up --force, ...
sc() { _sidecar_bin "$@"; }

# The four commands used daily.
scst()   { _sidecar_bin status; }
scdoc()  { _sidecar_bin doctor; }
scup()   { _sidecar_bin up "$@"; }
scdown() { _sidecar_bin down; }

# Force a reconnect even when the session looks healthy (costs one UC reset).
scnew()  { _sidecar_bin up --force; }

# Restart the virtual display only. Costs one UC reset: use with the lid open,
# or accept that the session will drop and come back on its own.
screstart() { _sidecar_bin restart-vdisp; }
