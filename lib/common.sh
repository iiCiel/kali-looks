# shellcheck shell=bash
# Shared helpers for the `looks` command and each look's look.sh.
# shellcheck disable=SC2034  # paths are used by the scripts that source this file

LOOKS_VERSION="0.2.0"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/kali-looks"
SRC_DIR="$DATA_DIR/src"           # pinned upstream sources
DL_DIR="$DATA_DIR/downloads"      # release archives, checked by SHA-256
STATE="$DATA_DIR/state"           # not in ~/.config: that folder changes with the session
BIN_DIR="$HOME/.local/bin"
LOCAL_SHARE="${XDG_DATA_HOME:-$HOME/.local/share}"

# Shells started outside the desktop (ssh, some tools) may lack these.
if [[ -z ${XDG_RUNTIME_DIR:-} && -d /run/user/$(id -u) ]]; then export XDG_RUNTIME_DIR="/run/user/$(id -u)"; fi

# Root commands run through this: sudo by default, LOOKS_ROOT=pkexec for a graphical prompt.
ROOT_CMD="${LOOKS_ROOT:-sudo}"

if [[ -t 1 ]]; then
  C_BLUE=$'\033[1;34m'; C_YEL=$'\033[1;33m'; C_RED=$'\033[1;31m'; C_GRN=$'\033[1;32m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_BLUE=""; C_YEL=""; C_RED=""; C_GRN=""; C_DIM=""; C_OFF=""
fi
log()  { printf '%s==>%s %s\n' "$C_BLUE" "$C_OFF" "$*"; }
ok()   { printf '%s  ✓%s %s\n' "$C_GRN" "$C_OFF" "$*"; }
warn() { printf '%s  !%s %s\n' "$C_YEL" "$C_OFF" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

as_root() { if [[ $ROOT_CMD == pkexec ]]; then pkexec "$@"; else sudo "$@"; fi; }

state_get() { [[ -f $STATE ]] && sed -n "s/^$1=//p" "$STATE" | tail -n 1; }
state_set() {
  mkdir -p "$(dirname "$STATE")"; touch "$STATE"
  sed -i "/^$1=/d" "$STATE"; printf '%s=%s\n' "$1" "$2" >> "$STATE"
}

apt_has() { apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/{print $2}' | grep -qv '(none)'; }
pkg_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"; }

# Install the packages that are missing (one password prompt).
need_packages() {
  local -a missing=(); local p
  for p in "$@"; do pkg_installed "$p" || missing+=("$p"); done
  [[ ${#missing[@]} -gt 0 ]] || return 0
  log "Installing packages: ${missing[*]} (asks for your password)"
  as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}" \
    || die "Installing ${missing[*]} failed."
}

# Fetch one pinned commit of a git repo into $SRC_DIR/<name>.
fetch_repo() {
  local name=$1 url=$2 commit=$3 dir="$SRC_DIR/$1"
  if [[ -d $dir/.git ]] && [[ $(git -C "$dir" rev-parse HEAD 2>/dev/null) == "$commit" ]]; then
    return 0
  fi
  rm -rf "$dir"; mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" remote add origin "$url"
  git -C "$dir" fetch -q --depth 1 origin "$commit" || die "Couldn't download $name ($url)."
  git -C "$dir" checkout -q FETCH_HEAD
}

sha_ok() { echo "$2  $1" | sha256sum -c --status; }

in_plasma() { [[ ${XDG_CURRENT_DESKTOP:-} == *KDE* ]] && pgrep -u "$(id -u)" -x plasmashell >/dev/null; }
is_wayland() { [[ ${XDG_SESSION_TYPE:-} == wayland ]]; }

qdbus() { if command -v qdbus6 >/dev/null; then qdbus6 "$@"; else qdbus "$@"; fi; }

# Run a Plasma desktop-scripting snippet in the running shell.
plasma_script() { qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$1"; }

restart_plasmashell() {
  if systemctl --user is-active -q plasma-plasmashell.service 2>/dev/null; then
    systemctl --user restart plasma-plasmashell.service
  else
    kquitapp6 plasmashell >/dev/null 2>&1 || pkill -u "$(id -u)" -x plasmashell || true
    sleep 1
    setsid plasmashell >/dev/null 2>&1 < /dev/null &
  fi
}

reconfigure_kwin() { qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true; }
