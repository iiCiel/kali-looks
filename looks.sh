#!/usr/bin/env bash
# looks: whole-desktop looks for Kali, each its own login-screen session.
#
#   looks list                     the looks, and which are set up
#   looks setup <look>             install or update a look (macos, winxp, win7, xfce)
#   looks sessions                 put the set-up looks on the login screen
#   looks switch [look]            log out and come back as another look ("base" = Xfce)
#   looks reset <look>             start a look's settings over from scratch
#   looks remove <look>            uninstall a look
#   looks rebuild win7             rebuild Windows 7 after a Plasma update
#   looks sessions remove          take the sessions off the login screen
#   looks auth [remove]            one password covers 30 minutes of admin prompts
#   looks desktop-rights [remove]  Turn Off, network, USB drives, brightness keys with Remote Desktop on
#   looks sandbox <look> start|stop|shot NAME|run CMD   a hidden session, for testing
#   looks wallpaper [look]         a look's wallpaper; fills in screens showing Plasma's blue default
#   looks dock-apps list|quit ID   running apps, windows or not (the macOS Tahoe Dock uses it)
#   looks help
set -Eeuo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=lib/sessions.sh
source "$HERE/lib/sessions.sh"

all_looks() { local d; for d in "$HERE"/looks/*/; do [[ -f $d/look.sh ]] && basename "$d"; done; }

load_look() {
  local id=$1
  LOOK_DIR="$HERE/looks/$id"
  [[ -f $LOOK_DIR/look.sh ]] || die "Unknown look '$id'. Try: looks list"
  LOOK_ID=$id
  LOOK_CFG="$CFG_ROOT/$id"
  export LOOK_ID LOOK_CFG
  # shellcheck source=/dev/null
  source "$LOOK_DIR/look.sh"
}

# ---- running things inside the look's own session --------------------------------
# During setup, commands run either in the look's real session (if you're logged into
# it) or in a hidden one. look_run runs as you; look_root as root with the same session.

SETUP_MODE=""
look_envs() {
  if [[ $SETUP_MODE == sandbox ]]; then
    sandbox_env "$LOOK_ID"; echo "DBUS_SESSION_BUS_ADDRESS=$(sandbox_bus "$LOOK_ID")"
  else
    local k; for k in HOME DISPLAY XAUTHORITY XDG_RUNTIME_DIR XDG_SESSION_TYPE XDG_CURRENT_DESKTOP \
      XDG_SESSION_DESKTOP KDE_FULL_SESSION KDE_SESSION_VERSION DESKTOP_SESSION LANG PATH USER LOGNAME \
      DBUS_SESSION_BUS_ADDRESS XDG_CONFIG_DIRS XDG_DATA_DIRS; do
      [[ -n ${!k:-} ]] && echo "$k=${!k}"
    done
    echo "XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$(readlink -f "$HOME/.config")}"
  fi
}
look_run() { local -a e; mapfile -t e < <(look_envs); env -i "${e[@]}" "$@"; }
look_root() {
  local -a e; mapfile -t e < <(look_envs)
  auth_window_open
  # PYTHONNOUSERSITE: root Python mustn't load packages from your ~/.local
  pkexec env "${e[@]}" PYTHONNOUSERSITE=1 SUDO_USER="$(id -un)" SUDO_UID="$(id -u)" SUDO_GID="$(id -g)" "$@"
}

# ---- commands ---------------------------------------------------------------------

look_ready() {
  ( load_look "$1" >/dev/null 2>&1 || exit 1
    if declare -F look_is_ready >/dev/null; then look_is_ready; else [[ -e $LOOK_CFG/.ready ]]; fi )
}

cmd_list() {
  local id title cur state info here
  cur=$(current_look)
  echo "Looks:"
  for id in $(all_looks); do
    info=$( (load_look "$id"; echo "${LOOK_IS_BASE:+base}|$LOOK_TITLE") )
    title=${info#*|}; here=$id
    # the Xfce look is your own Kali desktop, which the session tracks as "base"
    [[ ${info%%|*} == base ]] && here=base
    if look_ready "$id"; then state="${C_GRN}set up${C_OFF}"; else state="${C_DIM}not set up: looks setup $id${C_OFF}"; fi
    printf '  %s %-6s %-14s %s\n' "$([[ $here == "$cur" ]] && echo "*" || echo " ")" "$id" "$title" "$state"
  done
  [[ $cur == base ]] && ! look_ready xfce && echo "  (you're in your own Kali desktop)"
  true
}

cmd_setup() {
  local id=${1:-}
  [[ -n $id ]] || die "Which look? Try: looks list"
  load_look "$id"
  mkdir -p "$DATA_DIR" "$SRC_DIR" "$DL_DIR"
  if [[ -n ${LOOK_IS_BASE:-} ]]; then
    # It dresses your own Xfce desktop: no session of its own, so no hidden one to set
    # it up in either. Its installer checks it's inside Xfce.
    SETUP_MODE=live; look_prepare; look_setup "${@:2}"
    ok "$LOOK_TITLE is set up. Log out and back in so every app sends its menus to the menu bar."
    return 0
  fi
  need_packages xvfb imagemagick pkexec git curl
  ensure_config_link || die "Couldn't turn ~/.config into a link (see above)."
  sync_look_config "$id"
  look_prepare
  if [[ $(current_look) == "$id" ]] && pgrep -u "$(id -u)" -x plasmashell >/dev/null; then
    SETUP_MODE=live
  else
    SETUP_MODE=sandbox
    export LOOKS_SETUP=1
    log "Starting a hidden $LOOK_TITLE session to set it up in (your screen isn't touched)"
    trap 'cmd_sandbox "$LOOK_ID" stop >/dev/null 2>&1 || true' EXIT
    cmd_sandbox "$id" start
  fi
  local stamp; stamp=$(mktemp); touch "$stamp"
  look_setup
  touch "$LOOK_CFG/.ready"
  # the hidden session leaves KDE's global shortcuts switched off: the next login
  # puts KDE's defaults back (lib/shortcuts.py)
  rm -f "$LOOK_CFG/.kali-looks-shortcut-defaults"
  if [[ $SETUP_MODE == sandbox ]]; then cmd_sandbox "$id" stop >/dev/null; trap - EXIT; fi
  [[ $SETUP_MODE == sandbox ]] && fix_sandbox_paths "$id" "$stamp"
  rm -f "$stamp"
  ok "$LOOK_TITLE is set up."
  if grep -q '^# >>> kali-looks >>>' "$XSESSIONRC" 2>/dev/null; then cmd_sessions_install; else
    echo "  Next: looks sessions   (puts it on the login screen)"; fi
}

cmd_reset() {
  local id=${1:-}
  [[ -n $id ]] || die "Which look?"
  load_look "$id"
  [[ -z ${LOOK_IS_BASE:-} ]] || die "$LOOK_TITLE is your own Xfce desktop, not a separate one. To undo it: looks remove $id"
  [[ $(current_look) != "$id" ]] || die "You're logged into $LOOK_TITLE; switch to another session first."
  if [[ -d $LOOK_CFG ]]; then
    local bk; bk="$DATA_DIR/backup/$id-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$DATA_DIR/backup"; mv -T "$LOOK_CFG" "$bk"
    ok "Old $LOOK_TITLE settings moved to $bk"
  fi
  sync_look_config "$id"
  if declare -F look_after_reset >/dev/null; then look_after_reset; fi
  echo "  Run: looks setup $id"
}

# looks auth [remove]: one password covers 30 minutes of admin prompts
cmd_auth() {
  local script; script=$(mktemp)
  case ${1:-install} in
    install)
      {
        echo 'set -e'
        echo "install -D -m 755 '$HERE/lib/root/kali-looks-auth-window' /usr/local/libexec/kali-looks-auth-window"
        echo "install -D -m 755 '$HERE/lib/root/kali-looks-auth-open' /usr/local/libexec/kali-looks-auth-open"
        echo "install -D -m 644 '$HERE/lib/root/49-kali-looks.rules' /etc/polkit-1/rules.d/49-kali-looks.rules"
        echo "mkdir -p /run/kali-looks-auth && chmod 755 /run/kali-looks-auth && touch '/run/kali-looks-auth/$(id -un)'"
      } > "$script"
      pkexec bash "$script" || { rm -f "$script"; die "Couldn't set up the 30-minute window."; }
      ok "One password now covers 30 minutes of admin prompts (undo: looks auth remove)." ;;
    remove)
      {
        echo 'rm -f /etc/polkit-1/rules.d/49-kali-looks.rules /usr/local/libexec/kali-looks-auth-window /usr/local/libexec/kali-looks-auth-open'
        echo 'rm -rf /run/kali-looks-auth'
      } > "$script"
      pkexec bash "$script" && ok "Back to a password for every admin step." ;;
    *) die "usage: looks auth [remove]" ;;
  esac
  rm -f "$script"
}

# looks desktop-rights [remove]: Turn Off, network and USB drives without an admin
# password while Chrome Remote Desktop's session is open (lib/root/48-kali-looks-desktop.rules)
cmd_desktop_rights() {
  local script; script=$(mktemp)
  case ${1:-install} in
    install)
      {
        echo 'set -e'
        echo "sed 's/@USER@/$(id -un)/' '$HERE/lib/root/48-kali-looks-desktop.rules' > /etc/polkit-1/rules.d/48-kali-looks-desktop.rules"
        echo 'chmod 644 /etc/polkit-1/rules.d/48-kali-looks-desktop.rules'
      } > "$script"
      pkexec bash "$script" || { rm -f "$script"; die "Not installed."; }
      # Plasma's brightness service looks for screens once, when it starts
      systemctl --user try-restart plasma-powerdevil.service 2>/dev/null || true
      ok "Turn Off, network, USB drives and the brightness keys work without an admin password (undo: looks desktop-rights remove)." ;;
    remove)
      echo 'rm -f /etc/polkit-1/rules.d/48-kali-looks-desktop.rules' > "$script"
      pkexec bash "$script" && ok "Removed." ;;
    *) die "usage: looks desktop-rights [remove]" ;;
  esac
  rm -f "$script"
}

cmd_install() {
  mkdir -p "$BIN_DIR"
  ln -sf "$HERE/looks.sh" "$BIN_DIR/looks"
  # 0.1 kept its state in ~/.config/kali-looks
  [[ -f $STATE || ! -f $HOME/.config/kali-looks/state ]] || { mkdir -p "$DATA_DIR"; cp "$HOME/.config/kali-looks/state" "$STATE"; }
  ok "Installed: $BIN_DIR/looks  (make sure $BIN_DIR is on your PATH)"
}

usage() { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; }

case "${1:-help}" in
  list|ls|status) cmd_list ;;
  setup|apply) shift; cmd_setup "$@" ;;
  reset) shift; cmd_reset "$@" ;;
  rebuild|remove)
    [[ -n ${2:-} ]] || die "Which look? e.g. looks $1 win7"
    load_look "$2"
    declare -F "look_$1" >/dev/null || die "$LOOK_TITLE has nothing to $1."
    [[ $1 != remove || $(current_look) != "$2" ]] || die "You're logged into $LOOK_TITLE; switch to another session first."
    mkdir -p "$DATA_DIR" "$SRC_DIR"
    "look_$1" ;;
  install) cmd_install ;;
  sessions)
    case ${2:-install} in
      install|add) cmd_sessions_install ;;
      remove|uninstall) cmd_sessions_remove ;;
      *) die "usage: looks sessions [install|remove]" ;;
    esac ;;
  switch) shift; cmd_switch "$@" ;;
  auth) shift; cmd_auth "$@" ;;
  desktop-rights) shift; cmd_desktop_rights "$@" ;;
  session-hook) cmd_session_hook "${2:-}" ;;
  session-start) cmd_session_start ;;
  dock-apps) shift; exec "$HERE/looks/macos/dock-apps" "$@" ;;
  sandbox)
    [[ ${2:-} != xfce ]] || die "macOS (Xfce) is your own Xfce desktop; it has no hidden session."
    shift; cmd_sandbox "$@" ;;
  wallpaper)
    look=${2:-$(current_look)}; wp=$(look_wallpaper "$look")
    [[ -n $wp ]] || die "No wallpaper set for '$look'."
    echo "$wp"
    if [[ $(current_look) == "$look" ]] && q=$(command -v qdbus6 || command -v qdbus); then
      echo "screens filled in now: $(apply_wallpapers "$q" "$wp" || echo 0)"
      python3 "$HERE/lib/wallpapers.py" lock "$CFG_ROOT/$look" "$wp" >/dev/null || true
    else
      fill_wallpapers "$look" "$CFG_ROOT/$look"
    fi ;;
  -h|--help|help) usage ;;
  --version) echo "looks $LOOKS_VERSION" ;;
  *) usage; exit 2 ;;
esac
