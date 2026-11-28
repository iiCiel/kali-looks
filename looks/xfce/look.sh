# shellcheck shell=bash
# shellcheck disable=SC2034  # LOOK_* are read by the looks command
# macOS for Xfce: this folder is cupertino-xfce (its own repository until 0.1.0; its
# README has the details). Unlike the other looks it has no login session of its own: it
# dresses your normal Kali (Xfce) desktop, so it installs into your own settings, from
# inside your Xfce session. Extra arguments go to its installer, e.g.
#   looks setup xfce --dark
#   looks setup xfce --dry-run

LOOK_TITLE="macOS (Xfce)"
LOOK_IS_BASE=1
LOOK_CFG="$BASE_CFG"

in_xfce() { [[ $(current_look) == base ]] && pgrep -u "$(id -u)" -x xfce4-session >/dev/null; }

look_is_ready() { [[ -d ${XDG_DATA_HOME:-$HOME/.local/share}/cupertino-xfce/app ]]; }

look_prepare() { :; }

look_setup() {
  in_xfce || die "$LOOK_TITLE installs into your own Xfce desktop: log into Kali (Xfce) and run: looks setup xfce"
  log "Installing $LOOK_TITLE into your Xfce desktop (asks for your password)"
  local rc=0
  # pkexec: the password dialog works without a terminal too
  CUPERTINO_ROOT=${CUPERTINO_ROOT:-pkexec} "$LOOK_DIR/install.sh" -y "$@" 2>&1 \
    | tee "$DATA_DIR/xfce-install.log" || rc=$?
  [[ $rc -eq 0 ]] || die "The installer failed; see $DATA_DIR/xfce-install.log"
}

look_remove() {
  look_is_ready || { ok "$LOOK_TITLE isn't installed."; return 0; }
  in_xfce || die "Run this from inside your Xfce desktop: looks remove xfce"
  CUPERTINO_ROOT=${CUPERTINO_ROOT:-pkexec} "$LOOK_DIR/uninstall.sh" -y
}
