# shellcheck shell=bash
# One login-screen session per look. Before any X session starts, ~/.xsessionrc runs
# `looks session-hook "$DESKTOP_SESSION"`: it saves the settings of the session you
# left into that session's profile and loads the profile of the one you picked, so each
# look (and plain Xfce / Plasma) keeps its own settings and they never leak into each other.

PROFILE_DIR="$DATA_DIR/profiles"
FIRSTRUN_AUTOSTART="$CONF_HOME/autostart/kali-looks-firstrun.desktop"
XSESSIONRC="$HOME/.xsessionrc"
SESSION_LOG="$DATA_DIR/session.log"

# Session file names we install (without .desktop) and the look each one opens.
LOOK_SESSIONS=(
  "kali-looks-macos|macos|macOS (KDE Plasma)|startplasma-x11"
  "kali-looks-winxp|winxp|Windows XP (KDE Plasma)|startplasma-x11"
  "kali-looks-win7|win7|Windows 7 (AeroThemePlasma)|startatp"
)

# DESKTOP_SESSION -> "<profile> <look>" (look is empty for plain desktops)
session_profile() {
  local s=${1:-} target
  case $s in
    kali-looks-macos) echo "macos macos" ;;
    kali-looks-winxp) echo "winxp winxp" ;;
    kali-looks-win7|aerothemeplasma|aerothemeplasmax11) echo "win7 win7" ;;
    plasma|plasmax11|plasmawayland|*plasma*) echo "plasma" ;;
    xfce|xfce*|*xfce*) echo "xfce" ;;
    lightdm-xsession|default|"")
      target=$(readlink -f /etc/alternatives/x-session-manager 2>/dev/null || true)
      case $target in
        *startplasma*) echo "plasma" ;;
        *) echo "xfce" ;;
      esac ;;
    *) echo "other" ;;
  esac
}

# Runs before the session starts. Must be quick and must never stop the login.
cmd_session_hook() {
  local ds=${1:-} profile look cur
  read -r profile look <<<"$(session_profile "$ds")"
  mkdir -p "$PROFILE_DIR"
  echo "$(date -Is) session=$ds profile=$profile look=${look:-}" >> "$SESSION_LOG"
  [[ $profile == other ]] && return 0
  # The very first time, the live settings are your original desktop
  snapshot_original >/dev/null
  cur=$(state_get PROFILE || true)
  rm -f "$FIRSTRUN_AUTOSTART"
  [[ $cur == "$profile" ]] && return 0
  # Keep what you changed in the session you're leaving
  if [[ -n $cur ]]; then save_set "$PROFILE_DIR/$cur"; fi
  if ! restore_set "$PROFILE_DIR/$profile"; then
    # First time in this session: start from your original desktop...
    restore_set "$ORIG_DIR" || true
    # ...and, for a look, apply it once Plasma is up (Windows 7 runs its own setup)
    if [[ -n $look && $look != win7 ]]; then
      mkdir -p "$(dirname "$FIRSTRUN_AUTOSTART")"
      printf '[Desktop Entry]\nType=Application\nName=kali-looks first run\nExec=%s firstrun %s\nOnlyShowIn=KDE;\nX-KDE-autostart-phase=2\nNoDisplay=true\n' \
        "$BIN_DIR/looks" "$look" > "$FIRSTRUN_AUTOSTART"
    fi
  fi
  state_set PROFILE "$profile"
  state_set LOOK "${look:-}"
  state_set VARIANT ""
}

# Applies a look the first time its session starts (from an autostart entry).
cmd_firstrun() {
  local look=$1 i
  rm -f "$FIRSTRUN_AUTOSTART"
  for ((i = 0; i < 60; i++)); do
    qdbus org.kde.plasmashell /PlasmaShell >/dev/null 2>&1 && break
    sleep 1
  done
  sleep 2
  cmd_apply "$look" >> "$SESSION_LOG" 2>&1 || notify-send "kali-looks" "Couldn't apply the $look look; see $SESSION_LOG" 2>/dev/null || true
}

xsessionrc_hook() {
  cat <<'EOF'
# >>> kali-looks >>> (lets each login-screen session keep its own look; remove with: looks sessions remove)
if [ -x "$HOME/.local/bin/looks" ]; then
  "$HOME/.local/bin/looks" session-hook "${DESKTOP_SESSION:-}" >/dev/null 2>&1 || true
fi
# <<< kali-looks <<<
EOF
}

cmd_sessions_install() {
  local entry file look name exec script="$DATA_DIR/sessions-as-root.sh" id
  mkdir -p "$DATA_DIR" "$CONF_DIR" "$SRC_DIR" "$PROFILE_DIR"
  [[ -x $BIN_DIR/looks ]] || cmd_install
  snapshot_original
  # Get each look's files ready now (this can ask for your password), so the first
  # login into a look's session doesn't have to download anything.
  for id in macos winxp; do
    ( load_look "$id"; look_prepare )
  done
  {
    echo "set -e"
    for entry in "${LOOK_SESSIONS[@]}"; do
      IFS='|' read -r file look name exec <<<"$entry"
      if [[ $exec == startatp && ! -x /usr/bin/startatp ]]; then continue; fi
      cat <<EOF
cat > /usr/share/xsessions/$file.desktop <<'DESK'
[Desktop Entry]
Type=XSession
Name=$name
Comment=KDE Plasma with the $name look (kali-looks)
Exec=$exec
TryExec=$exec
DesktopNames=KDE
X-KaliLooks=$look
DESK
EOF
    done
    # AeroThemePlasma's own entries would duplicate "Windows 7": hide them
    echo 'for f in /usr/share/xsessions/aerothemeplasmax11.desktop /usr/share/wayland-sessions/aerothemeplasma.desktop; do'
    echo '  [ -f "$f" ] && ! grep -q "^NoDisplay=true" "$f" && echo "NoDisplay=true" >> "$f"'
    echo 'done; true'
  } > "$script"
  log "Adding the looks to the login screen (asks for your password)"
  as_root bash "$script" || die "Couldn't add the login-screen sessions."
  # The hook that switches settings when you log in
  touch "$XSESSIONRC"
  strip_marked "$XSESSIONRC"
  xsessionrc_hook >> "$XSESSIONRC"
  # The session you're in now owns the live settings
  if [[ -z $(state_get PROFILE || true) ]]; then
    local cur; read -r cur _ <<<"$(session_profile "${DESKTOP_SESSION:-}")"
    [[ $cur == other ]] || state_set PROFILE "$cur"
  fi
  ok "Log out and pick a look in the session menu of the login screen:"
  for entry in "${LOOK_SESSIONS[@]}"; do
    IFS='|' read -r file look name exec <<<"$entry"
    [[ -f /usr/share/xsessions/$file.desktop ]] && echo "    • $name"
  done
  return 0
}

cmd_sessions_remove() {
  local script="$DATA_DIR/sessions-remove-as-root.sh" entry file rest
  {
    echo "set -e"
    for entry in "${LOOK_SESSIONS[@]}"; do
      IFS='|' read -r file rest <<<"$entry"
      echo "rm -f /usr/share/xsessions/$file.desktop"
    done
    echo 'for f in /usr/share/xsessions/aerothemeplasmax11.desktop /usr/share/wayland-sessions/aerothemeplasma.desktop; do [ -f "$f" ] && sed -i "/^NoDisplay=true$/d" "$f"; done; true'
  } > "$script"
  log "Removing the looks from the login screen (asks for your password)"
  as_root bash "$script" || die "Couldn't remove the sessions."
  [[ -f $XSESSIONRC ]] && strip_marked "$XSESSIONRC"
  rm -f "$FIRSTRUN_AUTOSTART"
  ok "Removed. Your saved per-session settings stay in $PROFILE_DIR."
}

# Remove the marked kali-looks block from a file.
strip_marked() {
  sed -i '/^# >>> kali-looks >>>/,/^# <<< kali-looks <<</d' "$1"
}
