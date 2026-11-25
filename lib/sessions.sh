# shellcheck shell=bash
# Login-screen sessions, each with its own ~/.config.
#
# ~/.config is a symlink. Your own settings (Xfce and every app) live in $BASE_CFG.
# Each look has $CFG_ROOT/<look>: that look's desktop settings, plus links back to
# base for everything else (browsers, editors, Claude, ...), so apps behave the same
# in every session while the desktops never see each other's settings.
# ~/.xsessionrc runs `looks session-hook "$DESKTOP_SESSION"` before every X session;
# it points ~/.config at the tree that belongs to the session you picked.

CFG_ROOT="$DATA_DIR/config"
BASE_CFG="$CFG_ROOT/base"
SESSION_LOG="$DATA_DIR/session.log"
XSESSIONRC="$HOME/.xsessionrc"

# session id | look | name on the login screen | command | comment
LOOK_SESSIONS=(
  "kali-looks-macos|macos|macOS Tahoe|startplasma-x11|KDE Plasma dressed as macOS Tahoe"
  "kali-looks-winxp|winxp|Windows XP|startplasma-x11|KDE Plasma dressed as Windows XP"
  "kali-looks-win7|win7|Windows 7|startatp|KDE Plasma dressed as Windows 7 (AeroThemePlasma)"
)

session_field() { # session_field <look> <n>
  local s f; for s in "${LOOK_SESSIONS[@]}"; do
    IFS='|' read -r -a f <<<"$s"; [[ ${f[1]} == "$1" ]] && { echo "${f[$2]}"; return 0; }
  done; return 1
}

# DESKTOP_SESSION -> config tree
look_of_session() {
  case ${1:-} in
    kali-looks-*) echo "${1#kali-looks-}" ;;
    aerothemeplasma*) echo win7 ;;
    plasma*|*plasma*) echo plasma ;;
    *) echo base ;;
  esac
}

# Top-level ~/.config entries a look keeps for itself (desktop settings).
# Everything else is shared with your own settings.
look_owned() {
  case $1 in
    .seeded|*rc|kde*|kwin*|kscreen*|ksmserver*|kactivitymanagerd*|plasma*|KDE|Kvantum|kvantum*) return 0 ;;
    gtk-2.0|gtk-3.0|gtk-4.0|gtkrc*|xsettingsd|Trolltech.conf|qt5ct|qt6ct|fontconfig|menus|dconf) return 0 ;;
    autostart|systemd|environment.d|session|xdg-desktop-portal*|*portals.conf|mimeapps.list) return 0 ;;
    xfce4|Thunar|xfwm4|plank|picom|rofi|cupertino-xfce|kali-looks) return 0 ;;
    aerothemeplasma*|klassy|latte*|xplasma*|xp-*|mac-tahoe*|MacTahoe*) return 0 ;;
    baloo*|kxmlgui*|kconf_update*|spectacle*|dolphin*|konsole*|kate*) return 0 ;;
  esac
  return 1
}

# Turn the real ~/.config folder into a link to $BASE_CFG (once). Nothing moves on
# disk except the folder's name, so running programs keep working.
ensure_config_link() {
  local c="$HOME/.config"
  [[ -L $c ]] && return 0
  mkdir -p "$CFG_ROOT"
  if [[ -e $BASE_CFG ]]; then
    warn "$BASE_CFG already exists but ~/.config is a real folder; leaving both alone."
    return 1
  fi
  if [[ -d $c ]]; then
    mv -T "$c" "$BASE_CFG" && ln -s "$BASE_CFG" "$c"
  else
    mkdir -p "$BASE_CFG" && ln -s "$BASE_CFG" "$c"
  fi
}

point_config() { ln -sfn "$1" "$HOME/.config.kali-looks" && mv -Tf "$HOME/.config.kali-looks" "$HOME/.config"; }

# Bring a look's tree up to date with base: link shared app folders, copy shared
# top-level files once, move app folders created inside the look over to base.
sync_look_config() {
  local dir="$CFG_ROOT/$1" e name
  mkdir -p "$dir"
  shopt -s dotglob nullglob
  for e in "$dir"/*; do
    name=${e##*/}
    [[ -L $e || ! -d $e ]] && continue
    look_owned "$name" && continue
    if [[ ! -e $BASE_CFG/$name ]]; then mv -T "$e" "$BASE_CFG/$name" && ln -s "$BASE_CFG/$name" "$e"; fi
  done
  for e in "$BASE_CFG"/*; do
    name=${e##*/}
    look_owned "$name" && continue
    if [[ -L $dir/$name ]]; then [[ -e $dir/$name ]] || ln -sfn "$e" "$dir/$name"; continue; fi
    [[ -e $dir/$name ]] && continue
    if [[ -d $e ]]; then ln -s "$e" "$dir/$name"; else cp -p "$e" "$dir/$name"; fi
  done
  for e in "$dir"/*; do if [[ -L $e && ! -e $e ]]; then rm -f "$e"; fi; done
  if [[ ! -e $dir/.seeded ]]; then
    for name in mimeapps.list dconf systemd; do
      if [[ -e $BASE_CFG/$name && ! -e $dir/$name ]]; then cp -a "$BASE_CFG/$name" "$dir/"; fi
    done
    if [[ -f $BASE_CFG/gtk-3.0/bookmarks ]]; then mkdir -p "$dir/gtk-3.0"; cp -n "$BASE_CFG/gtk-3.0/bookmarks" "$dir/gtk-3.0/"; fi
    touch "$dir/.seeded"
  fi
  shopt -u dotglob nullglob
}

# One time: KDE sessions that ran before kali-looks 0.2 wrote their settings into your
# own config. Move them aside (kept in a backup) so Xfce is exactly as it was.
clean_base_once() {
  local flag="$DATA_DIR/.base-cleaned" bk name g="$BASE_CFG/gtk-3.0"
  [[ -e $flag ]] && return 0
  bk="$DATA_DIR/backup/kde-leftovers-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$bk/gtk-3.0"
  for name in kdedefaults kdeglobals plasma-localerc Kvantum aerothemeplasmarc kactivitymanagerdrc \
      kactivitymanagerd-statsrc kconf_updaterc kded5rc kded6rc ktimezonedrc kwinrulesrc kwinrc \
      plasma-org.kde.plasma.desktop-appletsrc plasma-io.gitgud.wackyideas.desktop-appletsrc \
      plasma-welcomerc plasmashellrc plasmarc powermanagementprofilesrc powerdevilrc xsettingsd \
      bluedevilglobalrc session dolphinrc konsolerc konsolesshconfig kwalletrc Trolltech.conf gtkrc \
      gtkrc-2.0 kcminputrc kglobalshortcutsrc ksmserverrc KDE spectaclerc ksplashrc kscreenlockerrc \
      krunnerrc kxkbrc breezerc auroraerc gtk-4.0 kwinoutputconfig.json plasmanotifyrc \
      systemsettingsrc kiorc kservicemenurc baloofilerc; do
    if [[ -e $BASE_CFG/$name || -L $BASE_CFG/$name ]]; then mv "$BASE_CFG/$name" "$bk/"; fi
  done
  for name in colors.css assets settings.ini; do
    if [[ -e $g/$name ]]; then mv "$g/$name" "$bk/gtk-3.0/"; fi
  done
  if [[ -f $g/gtk.css ]]; then
    cp -p "$g/gtk.css" "$bk/gtk-3.0/gtk.css"
    sed -i "/^@import 'colors.css';\$/d" "$g/gtk.css"
    [[ -s $g/gtk.css ]] || rm -f "$g/gtk.css"
  fi
  touch "$flag"
}

# Runs before every X session starts. Quick, and never stops the login.
cmd_session_hook() {
  local ds=${1:-} look target
  mkdir -p "$DATA_DIR"
  look=$(look_of_session "$ds")
  {
    echo "$(date '+%F %T') session=$ds look=$look"
    ensure_config_link || exit 0
    clean_base_once
    if [[ $look == base ]]; then
      target=$BASE_CFG
    else
      sync_look_config "$look"
      target="$CFG_ROOT/$look"
    fi
    point_config "$target"
    state_set ACTIVE "$look"
    systemctl --user daemon-reload 2>/dev/null || true
  } >>"$SESSION_LOG" 2>&1 || true
}

hook_block() {
  cat <<'EOF'
# >>> kali-looks >>> (gives each login-screen look its own settings; remove with: looks sessions remove)
if [ -x "$HOME/.local/bin/looks" ]; then
  "$HOME/.local/bin/looks" session-hook "${DESKTOP_SESSION:-}" >/dev/null 2>&1 || true
fi
# <<< kali-looks <<<
EOF
}

strip_marked() { # drop the kali-looks block from a file
  [[ -f $1 ]] || return 0
  sed -i '/^# >>> kali-looks >>>/,/^# <<< kali-looks <<</d' "$1"
}

cmd_sessions_install() {
  [[ -x $BIN_DIR/looks ]] || cmd_install
  local s script id look name cmd comment
  script=$(mktemp)
  {
    echo 'set -e'
    echo 'rm -f /usr/share/xsessions/kali-looks-*.desktop'
    for s in "${LOOK_SESSIONS[@]}"; do
      IFS='|' read -r id look name cmd comment <<<"$s"
      [[ $cmd == startatp && ! -x /usr/bin/startatp ]] && continue
      [[ $look != win7 && ! -e $CFG_ROOT/$look/.ready ]] && continue
      printf "cat > /usr/share/xsessions/%s.desktop <<'EOF'\n" "$id"
      printf '[Desktop Entry]\nType=XSession\nName=%s\nComment=%s\nExec=%s\nTryExec=%s\nDesktopNames=KDE\nX-KaliLooks=%s\n' \
        "$name" "$comment" "$cmd" "$cmd" "$look"
      echo 'EOF'
    done
    # AeroThemePlasma ships its own session entries; ours replaces them (same command).
    echo 'for f in /usr/share/xsessions/aerothemeplasmax11.desktop /usr/share/wayland-sessions/aerothemeplasma.desktop; do'
    echo '  if [ -f "$f" ] && ! grep -q "^NoDisplay=true" "$f"; then echo "NoDisplay=true" >> "$f"; fi; done'
  } > "$script"
  log "Adding the looks to the login screen (asks for your password)"
  as_root bash "$script" || { rm -f "$script"; die "Couldn't write the session files."; }
  rm -f "$script"
  touch "$XSESSIONRC"
  strip_marked "$XSESSIONRC"
  hook_block >> "$XSESSIONRC"
  ensure_config_link || true
  install_switcher
  ok "Log out and pick a look from the session menu on the login screen."
}

cmd_sessions_remove() {
  local script
  script=$(mktemp)
  {
    echo 'rm -f /usr/share/xsessions/kali-looks-*.desktop'
    echo 'for f in /usr/share/xsessions/aerothemeplasmax11.desktop /usr/share/wayland-sessions/aerothemeplasma.desktop; do'
    echo '  if [ -f "$f" ]; then sed -i "/^NoDisplay=true$/d" "$f"; fi; done'
  } > "$script"
  as_root bash "$script" || warn "Couldn't remove the session files."
  rm -f "$script"
  strip_marked "$XSESSIONRC"
  rm -f "$LOCAL_SHARE/applications/kali-looks-switch.desktop"
  if [[ -L $HOME/.config && -d $BASE_CFG ]]; then
    rm -f "$HOME/.config" && mv -T "$BASE_CFG" "$HOME/.config"
    ok "Your ~/.config is your own settings folder again. Each look's settings stay in $CFG_ROOT."
  fi
  ok "Sessions removed."
}

# ---- switching from inside a session -------------------------------------------

install_switcher() {
  mkdir -p "$LOCAL_SHARE/applications"
  cat > "$LOCAL_SHARE/applications/kali-looks-switch.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Switch Look
GenericName=Log out into another desktop look
Comment=macOS, Windows XP, Windows 7 or your Kali desktop
Exec=$BIN_DIR/looks switch
Icon=preferences-desktop-theme-global
Categories=Settings;DesktopSettings;
Keywords=theme;look;session;macos;windows;xp;
EOF
}

current_look() { local a; a=$(state_get ACTIVE || true); echo "${a:-base}"; }

set_next_session() {
  gdbus call --system --dest org.freedesktop.Accounts \
    --object-path "/org/freedesktop/Accounts/User$(id -u)" \
    --method org.freedesktop.Accounts.User.SetXSession "$1" >/dev/null 2>&1 || true
  printf '[Desktop]\nSession=%s\n' "$1" > "$HOME/.dmrc"
}

base_session_id() {
  local f
  for f in /usr/share/xsessions/xfce.desktop /usr/share/xsessions/xfce4.desktop; do
    [[ -f $f ]] && { basename "$f" .desktop; return; }
  done
  echo lightdm-xsession
}

logout_now() {
  if pgrep -u "$(id -u)" -x plasmashell >/dev/null; then
    qdbus org.kde.Shutdown /Shutdown org.kde.Shutdown.logout 2>/dev/null \
      || qdbus org.kde.ksmserver /KSMServer org.kde.KSMServerInterface.logout 0 0 0
  elif pgrep -u "$(id -u)" -x xfce4-session >/dev/null; then
    xfce4-session-logout --logout --fast
  else
    loginctl terminate-session "${XDG_SESSION_ID:-}"
  fi
}

cmd_switch() {
  local pick=${1:-} cur s id look name i
  local -a ids=(base) names=("Kali (Xfce)") args=()
  cur=$(current_look)
  for s in "${LOOK_SESSIONS[@]}"; do
    IFS='|' read -r id look name _ <<<"$s"
    [[ -f /usr/share/xsessions/$id.desktop ]] && { ids+=("$look"); names+=("$name"); }
  done
  if [[ -z $pick ]]; then
    if command -v kdialog >/dev/null && [[ ${XDG_CURRENT_DESKTOP:-} == *KDE* ]]; then
      for i in "${!ids[@]}"; do args+=("${ids[i]}" "${names[i]}" "$([[ ${ids[i]} == "$cur" ]] && echo on || echo off)"); done
      pick=$(kdialog --title "Switch Look" --radiolist "Log out and come back as:" "${args[@]}") || return 0
    else
      for i in "${!ids[@]}"; do args+=("$([[ ${ids[i]} == "$cur" ]] && echo TRUE || echo FALSE)" "${ids[i]}" "${names[i]}"); done
      pick=$(zenity --list --radiolist --title "Switch Look" --text "Log out and come back as:" \
        --column "" --column id --column Look --hide-column 2 --print-column 2 \
        --width 320 --height 280 "${args[@]}" 2>/dev/null) || return 0
    fi
  fi
  [[ -n $pick ]] || return 0
  if [[ $pick == base ]]; then id=$(base_session_id); else id="kali-looks-$pick"; fi
  [[ $pick == base || -f /usr/share/xsessions/$id.desktop ]] || die "No login session for '$pick'. Run: looks sessions"
  set_next_session "$id"
  [[ $pick == "$cur" ]] && return 0
  logout_now
}

# ---- a hidden session, to set up and check a look without logging out ---------
# Runs on its own X display with a home folder whose .config is the look's tree and
# whose .local is your real one, so everything installed there is what you'll get.

sandbox_home() { echo "$DATA_DIR/sandbox/$1/home"; }
sandbox_runtime() { echo "/tmp/kali-looks-sandbox-$(id -u)-$1"; }
sandbox_display() { case $1 in macos) echo :5 ;; winxp) echo :6 ;; win7) echo :7 ;; *) echo :8 ;; esac; }

sandbox_env() { # prints KEY=VALUE lines
  local look=$1 h rt d
  h=$(sandbox_home "$look"); rt=$(sandbox_runtime "$look"); d=$(sandbox_display "$look")
  printf '%s\n' "HOME=$h" "DISPLAY=$d" "XDG_RUNTIME_DIR=$rt" "XDG_SESSION_TYPE=x11" \
    "XDG_CURRENT_DESKTOP=KDE" "XDG_SESSION_DESKTOP=KDE" "KDE_FULL_SESSION=true" "KDE_SESSION_VERSION=6" \
    "DESKTOP_SESSION=kali-looks-$look" "LANG=${LANG:-C.UTF-8}" \
    "PATH=$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    "USER=$USER" "LOGNAME=$USER" "SHELL=/bin/bash" "XDG_CONFIG_HOME=$h/.config"
}

sandbox_prepare() {
  local look=$1 h d
  h=$(sandbox_home "$look")
  ensure_config_link || die "Couldn't set up ~/.config."
  sync_look_config "$look"
  mkdir -p "$h/.cache"
  ln -sfn "$CFG_ROOT/$look" "$h/.config"
  ln -sfn "$HOME/.local" "$h/.local"
  for d in Desktop Documents Downloads Music Pictures Videos Templates Public .icons .mozilla .themes .fonts; do
    [[ -e $HOME/$d ]] && ln -sfn "$HOME/$d" "$h/$d"
  done
  true
}

sandbox_bus() {
  local look=$1 p d
  d=$(sandbox_display "$look")
  for p in $(pgrep -u "$(id -u)" -x plasmashell); do
    if tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | grep -qx "DISPLAY=$d"; then
      tr '\0' '\n' < "/proc/$p/environ" | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p'; return 0
    fi
  done
  return 1
}

cmd_sandbox() {
  local look=${1:-} action=${2:-} d rt h cmd log p i
  [[ -n $look && -n $action ]] || die "usage: looks sandbox <look> start|stop|shot NAME|run CMD..."
  d=$(sandbox_display "$look"); rt=$(sandbox_runtime "$look"); h=$(sandbox_home "$look")
  log="$DATA_DIR/sandbox/$look/session.log"
  case $action in
    start)
      sandbox_prepare "$look"
      mkdir -p "$rt"; chmod 700 "$rt"
      if ! pgrep -f "Xvfb $d " >/dev/null; then
        setsid Xvfb "$d" -screen 0 "${SANDBOX_SIZE:-1920x1080}x24" +extension GLX -nolisten tcp >"$DATA_DIR/sandbox/$look/xvfb.log" 2>&1 < /dev/null &
        sleep 2
      fi
      cmd=$(session_field "$look" 3 2>/dev/null || echo startplasma-x11)
      mapfile -t env_kv < <(sandbox_env "$look")
      setsid env -i "${env_kv[@]}" dbus-run-session "$cmd" >"$log" 2>&1 < /dev/null &
      for i in $(seq 60); do sandbox_bus "$look" >/dev/null && break; sleep 1; done
      sandbox_bus "$look" >/dev/null || die "The hidden $look session didn't start (see $log)."
      ok "Hidden $look session running on $d" ;;
    stop)
      for p in $(pgrep -u "$(id -u)"); do
        tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | grep -qx "DISPLAY=$d" && kill "$p" 2>/dev/null
      done
      sleep 2; pkill -f "Xvfb $d " || true
      ok "Hidden $look session stopped" ;;
    shot)
      mkdir -p "$DATA_DIR/sandbox/$look/shots"
      DISPLAY=$d import -window root "$DATA_DIR/sandbox/$look/shots/${3:-shot}.png"
      echo "$DATA_DIR/sandbox/$look/shots/${3:-shot}.png" ;;
    run)
      shift 2
      mapfile -t env_kv < <(sandbox_env "$look")
      env -i "${env_kv[@]}" DBUS_SESSION_BUS_ADDRESS="$(sandbox_bus "$look")" "$@" ;;
    *) die "usage: looks sandbox <look> start|stop|shot NAME|run CMD..." ;;
  esac
}
