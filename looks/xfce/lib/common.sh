# shellcheck shell=bash
# Shared helpers for install.sh and uninstall.sh.
# shellcheck disable=SC2034  # paths below are used by the scripts that source this file

DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/cupertino-xfce"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/cupertino-xfce"
SRC_DIR="$DATA_DIR/src"
BACKUP_ROOT="$DATA_DIR/backups"
GTK_CSS="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/gtk.css"
AUTOSTART_PICOM="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/cupertino-xfce-picom.desktop"
AUTOSTART_MENUD="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/cupertino-xfce-menud.desktop"
AUTOSTART_PLANK="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/cupertino-xfce-plank.desktop"
LAUNCHPAD_DESKTOP="${XDG_DATA_HOME:-$HOME/.local/share}/applications/cupertino-launchpad.desktop"
GREETER_CONF="/etc/lightdm/lightdm-gtk-greeter.conf"

# Root commands run through this. sudo by default; set CUPERTINO_ROOT=pkexec to use a
# graphical password prompt instead (handy when there is no terminal).
ROOT_CMD="${CUPERTINO_ROOT:-sudo}"

if [[ -t 1 ]]; then
  C_BLUE=$'\033[1;34m'; C_YEL=$'\033[1;33m'; C_RED=$'\033[1;31m'; C_GRN=$'\033[1;32m'; C_OFF=$'\033[0m'
else
  C_BLUE=""; C_YEL=""; C_RED=""; C_GRN=""; C_OFF=""
fi
log()  { printf '%s==>%s %s\n' "$C_BLUE" "$C_OFF" "$*"; }
ok()   { printf '%s  ✓%s %s\n' "$C_GRN" "$C_OFF" "$*"; }
warn() { printf '%s  !%s %s\n' "$C_YEL" "$C_OFF" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

# Run a bash script as root (one password prompt per call).
as_root_script() {
  local script=$1
  if [[ $ROOT_CMD == pkexec ]]; then
    pkexec bash "$script"
  else
    sudo bash "$script"
  fi
}

# Set an xfconf property, creating it with the given type if it doesn't exist yet.
xset_prop() {
  local ch=$1 prop=$2 type=$3 val=$4
  if xfconf-query -c "$ch" -p "$prop" >/dev/null 2>&1; then
    xfconf-query -c "$ch" -p "$prop" -s "$val"
  else
    xfconf-query -c "$ch" -p "$prop" -n -t "$type" -s "$val"
  fi
}

# Remove a marked cupertino-xfce block from a file (gtk.css etc.).
strip_block() {
  local f=$1
  [[ -f $f ]] || return 0
  sed -i '/>>> cupertino-xfce/,/<<< cupertino-xfce/d' "$f"
}

require_xfce_session() {
  [[ $EUID -ne 0 ]] || die "Run this as your normal user, not root. It asks for your password when it needs it."
  command -v apt-get >/dev/null || die "This needs a Debian-based system (Kali, Debian, Ubuntu…)."
  pgrep -u "$(id -u)" -x xfce4-session >/dev/null || die "No Xfce session found. Run this from inside your Xfce desktop."
  [[ -n ${DISPLAY:-} ]] || die "DISPLAY isn't set. Run this from a terminal inside your Xfce desktop."
  if [[ ${XDG_SESSION_TYPE:-x11} == wayland ]]; then
    die "Xfce on Wayland isn't supported yet (picom and the global menu need X11). Log in with the normal Xfce (X11) session."
  fi
}
