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
HIDDEN_SESSIONS="/usr/share/xsessions/aerothemeplasmax11.desktop /usr/share/wayland-sessions/aerothemeplasma.desktop /usr/share/xsessions/plasmax11.desktop /usr/share/xsessions/plasma.desktop /usr/share/wayland-sessions/plasma.desktop /usr/share/wayland-sessions/xfce-wayland.desktop"

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
    .seeded|.home|k*rc|kde*|kwin*|kscreen*|ksmserver*|kactivitymanagerd*|plasma*|KDE|Kvantum|kvantum*) return 0 ;;
    dolphinrc|katerc|spectaclerc|breezerc|auroraerc|powermanagementprofilesrc|powerdevilrc) return 0 ;;
    systemsettingsrc|bluedevilglobalrc|baloofilerc|*plasma*rc) return 0 ;;
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
  local c="$HOME/.config" t
  if [[ -L $c ]]; then
    t=$(readlink -f "$c")
    [[ $t == "$CFG_ROOT"/* && -d $t ]] && return 0
    warn "\$HOME/.config is a link kali-looks didn't make ($t); leaving it alone."
    return 1
  fi
  mkdir -p "$CFG_ROOT"
  if [[ -e $BASE_CFG ]]; then
    warn "$BASE_CFG already exists but ~/.config is a real folder; leaving both alone."
    return 1
  fi
  if [[ -d $c ]]; then
    mv -T "$c" "$BASE_CFG" && ln -sT "$BASE_CFG" "$c"
  else
    mkdir -p "$BASE_CFG" && ln -sT "$BASE_CFG" "$c"
  fi
}

point_config() { ln -sfn "$1" "$HOME/.config.kali-looks" && mv -Tf "$HOME/.config.kali-looks" "$HOME/.config"; }

# Bring a look's tree up to date with base: link shared app folders, copy shared
# top-level files once, move app folders created inside the look over to base.
sync_look_config() {
  local dir="$CFG_ROOT/$1" e name
  mkdir -p "$dir"
  shopt -s dotglob nullglob
  adopt_app_folders
  for e in "$BASE_CFG"/*; do
    name=${e##*/}
    look_owned "$name" && continue
    if [[ -L $dir/$name ]]; then [[ -e $dir/$name ]] || ln -sfn "$e" "$dir/$name"; continue; fi
    [[ -e $dir/$name ]] && continue
    if [[ -d $e ]]; then ln -s "$e" "$dir/$name"
    elif [[ -L $e ]]; then cp -P "$e" "$dir/$name"
    elif [[ -f $e ]]; then cp -p "$e" "$dir/$name"
    fi
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

# App folders created while a look was running (a new app, or an app first opened
# there) move into your own settings, from every look, so all sessions share them.
# If both sides already have one, the look keeps its copy and the log says so.
adopt_app_folders() {
  local d e name
  shopt -s dotglob nullglob
  for d in "$CFG_ROOT"/*/; do
    d=${d%/}; [[ $d == "$BASE_CFG" ]] && continue
    for e in "$d"/*; do
      name=${e##*/}
      [[ -L $e || ! -d $e ]] && continue
      look_owned "$name" && continue
      if [[ ! -e $BASE_CFG/$name ]]; then
        mv -T "$e" "$BASE_CFG/$name" && ln -s "$BASE_CFG/$name" "$e"
      else
        echo "note: ${d##*/} has its own ~/.config/$name (your own settings have one too); not merged"
      fi
    done
  done
  shopt -u dotglob nullglob
}

# A few desktop settings live outside ~/.config: the default pointer and the GTK 2 theme.
# Each look keeps its own copy (in <tree>/.home); the hook links the right one in.
HOME_OWNED=(.gtkrc-2.0 .icons/default .local/share/icons/default)
swap_home_files() { # swap_home_files <from-look> <to-look>
  local from=$1 to=$2 rel p store
  for rel in "${HOME_OWNED[@]}"; do
    p="$HOME/$rel"
    # whatever the last session left there (a real file, not one of our links) is its own
    if [[ -e $p || -L $p ]] && ! [[ -L $p && $(readlink "$p") == "$CFG_ROOT"/* ]]; then
      store="$CFG_ROOT/$from/.home/$rel"
      mkdir -p "$(dirname "$store")"; rm -rf "$store"; mv -T "$p" "$store"
    fi
    rm -f "$p"
    store="$CFG_ROOT/$to/.home/$rel"
    if [[ -e $store || -L $store ]]; then mkdir -p "$(dirname "$p")"; ln -sT "$store" "$p"; fi
  done
}

# One time: KDE sessions that ran before kali-looks 0.2 wrote their settings into your
# own config. Move them aside (kept in a backup) so Xfce is exactly as it was.
clean_base_once() {
  local flag="$DATA_DIR/.base-cleaned" bk name g="$BASE_CFG/gtk-3.0"
  [[ -e $flag ]] && return 0
  # They become the plain Plasma session's own settings (it gets its own tree, like a
  # look); if that tree already exists they go to a backup instead.
  if [[ -e $CFG_ROOT/plasma ]]; then bk="$DATA_DIR/backup/kde-leftovers-$(date +%Y%m%d-%H%M%S)"
  else bk="$CFG_ROOT/plasma"; fi
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

# Runs before every X session starts. Quick, and never stops the login. Prints the
# config folder's real path: ~/.xsessionrc exports it as XDG_CONFIG_HOME (some tools
# refuse to write through the ~/.config link).
cmd_session_hook() {
  local ds=${1:-} look target="" prev ok=""
  mkdir -p "$DATA_DIR"
  look=$(look_of_session "$ds")
  # Chrome Remote Desktop's own desktop (when nobody is logged in at the laptop) is your
  # Xfce: use your settings, but don't repoint ~/.config under a session that may start
  # at the laptop meanwhile.
  if [[ ${CHROME_REMOTE_DESKTOP_SESSION:-} == 1 ]]; then
    echo "$(date '+%F %T') session=$ds (Chrome Remote Desktop) look=base, ~/.config left as is" >>"$SESSION_LOG"
    [[ -d $BASE_CFG ]] && echo "$BASE_CFG"
    return 0
  fi
  {
    echo "$(date '+%F %T') session=$ds look=$look"
    clear_crd_env
    ensure_config_link || exit 0
    clean_base_once
    if [[ $look == base ]]; then
      target=$BASE_CFG
    else
      sync_look_config "$look"
      target="$CFG_ROOT/$look"
    fi
    adopt_app_folders
    prev=$(current_look)
    point_config "$target" && ok=1
    swap_home_files "$prev" "$look" || echo "warning: couldn't swap the pointer/GTK2 files"
    state_set ACTIVE "$look"
    systemctl --user daemon-reload 2>/dev/null || true
    reset_portals stop
    if [[ $look != base ]]; then
      # Kali's Xfce sets QT_QPA_PLATFORMTHEME=qt5ct, and when its desktop ran first
      # (Remote Desktop at boot) that stays behind: KDE then ignores the look's colors
      # and fonts (dark menus, wrong font). KDE uses its own platform theme.
      systemctl --user unset-environment QT_QPA_PLATFORMTHEME 2>/dev/null || true
      install_session_start "$target"
      [[ -x $HERE/looks/$look/before-session ]] && "$HERE/looks/$look/before-session" "$target"
    fi
  } >>"$SESSION_LOG" 2>&1 || true
  [[ -n $ok || $(readlink -f "$HOME/.config" 2>/dev/null) == "$target" ]] && [[ -n $target ]] && echo "$target"
  true
}

# Chrome Remote Desktop's own desktop puts its audio server, display and agent socket
# into the shared systemd environment. When you log in at the laptop while it runs,
# your desktop would start with them (mic and sound go to Remote Desktop), and a
# moment later its cleanup removes DISPLAY too (shortcuts like Print can't open apps).
CRD_ONLY_VARS=(CHROME_REMOTE_DESKTOP_AUDIO_PIPE CHROME_CONFIG_HOME CHROME_REMOTE_DESKTOP_SESSION
  CHROME_USER_DATA_DIR PIPEWIRE_REMOTE PULSE_CONFIG_PATH PULSE_RUNTIME_PATH PULSE_SINK
  PULSE_STATE_PATH GDK_BACKEND)
clear_crd_env() {
  local env; env=$(systemctl --user show-environment 2>/dev/null) || return 0
  local unset=("${CRD_ONLY_VARS[@]}")
  grep -q '^SSH_AUTH_SOCK=.*crd_ssh_auth_sock' <<<"$env" && unset+=(SSH_AUTH_SOCK)
  systemctl --user unset-environment "${unset[@]}" 2>/dev/null || true
}
# Put this session's display back if Remote Desktop's late cleanup removed it.
restore_session_env() {
  [[ -n ${DISPLAY:-} ]] || return 0
  local env; env=$(systemctl --user show-environment 2>/dev/null) || return 0
  if ! grep -qx "DISPLAY=$DISPLAY" <<<"$env" || grep -qE '^(PULSE_RUNTIME_PATH|PIPEWIRE_REMOTE)=' <<<"$env"; then
    clear_crd_env
    systemctl --user import-environment DISPLAY XAUTHORITY ${XDG_SESSION_ID:+XDG_SESSION_ID} 2>/dev/null || true
    dbus-update-activation-environment DISPLAY XAUTHORITY >/dev/null 2>&1 || true
    echo "$(date '+%F %T') session-start: put DISPLAY back after Remote Desktop's cleanup" >>"$SESSION_LOG"
  fi
}

# The desktop portal (screenshots, screen sharing, file pickers) keeps the desktop
# settings of whichever session started it first, e.g. Chrome Remote Desktop's Xfce
# at boot. Stop it before a session starts; Plasma looks also restart it once Plasma
# has published its own settings (looks session-start).
reset_portals() { # reset_portals stop|restart
  local u=(xdg-desktop-portal.service xdg-desktop-portal-gtk.service xdg-desktop-portal-kde.service)
  if [[ $1 == stop ]]; then systemctl --user stop "${u[@]}" 2>/dev/null || true
  else systemctl --user stop "${u[1]}" 2>/dev/null; systemctl --user try-restart "${u[0]}" 2>/dev/null || true; fi
}

install_session_start() { # install_session_start <look config tree>
  local f="$1/autostart/kali-looks-session-start.desktop"
  mkdir -p "$1/autostart"
  cat >"$f" <<EOF
[Desktop Entry]
Type=Application
Name=kali-looks session start
Exec=$BIN_DIR/looks session-start
NoDisplay=true
OnlyShowIn=KDE;
X-KDE-autostart-phase=1
EOF
}

# Runs inside a Plasma look once it's up: portal on Plasma's settings, and screens
# that never got a wallpaper (setup ran on one hidden screen) get screen 1's.
cmd_session_start() {
  restore_session_env
  local look; look=$(current_look)
  [[ -x $HERE/looks/$look/after-start ]] && "$HERE/looks/$look/after-start" >>"$SESSION_LOG" 2>&1
  # Remote Desktop notices the login a few seconds late; watch for its cleanup.
  ( for _ in $(seq 30); do sleep 1; restore_session_env; done ) >/dev/null 2>&1 &
  unset PULSE_RUNTIME_PATH PULSE_SINK PIPEWIRE_REMOTE CHROME_REMOTE_DESKTOP_SESSION
  reset_portals restart
  local q; q=$(command -v qdbus6 || command -v qdbus) || return 0
  local i; for i in $(seq 20); do "$q" org.kde.plasmashell /PlasmaShell >/dev/null 2>&1 && break; sleep 1; done
  "$q" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '
    var ds = desktops(), img = "", g = ["Wallpaper","org.kde.image","General"];
    for (var i = 0; i < ds.length; i++) if (ds[i].screen == 0 && ds[i].wallpaperPlugin == "org.kde.image") {
      ds[i].currentConfigGroup = g; img = ds[i].readConfig("Image"); }
    if (img != "") for (var i = 0; i < ds.length; i++) {
      var d = ds[i]; if (d.wallpaperPlugin != "org.kde.image") continue;
      d.currentConfigGroup = g; if (d.readConfig("Image") == "") d.writeConfig("Image", img); }' >/dev/null 2>&1 || true
  echo "$(date '+%F %T') session-start look=$(current_look)" >>"$SESSION_LOG"
}

# Setup in a hidden session runs with HOME set to the sandbox, and installers write
# that path into their files. Point everything written during setup at your real home.
fix_sandbox_paths() { # fix_sandbox_paths <look> <stamp file>
  local look=$1 stamp=$2 sb f n=0
  sb=$(sandbox_home "$look")
  while IFS= read -r -d '' f; do
    grep -qIF "$sb" "$f" 2>/dev/null || continue
    sed -i "s#$sb#$HOME#g" "$f" && n=$((n+1))
  done < <(find "$CFG_ROOT/$look" "$HOME/.local/share" "$HOME/.themes" "$HOME/.icons" \
             "$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")" \
             -path "$DATA_DIR" -prune -o -type f -newer "$stamp" -print0 2>/dev/null)
  find "$CFG_ROOT/$look" -type f -print0 2>/dev/null | xargs -0r grep -lIF "$sb" 2>/dev/null \
    | while IFS= read -r f; do sed -i "s#$sb#$HOME#g" "$f"; done
  [[ $n -gt 0 ]] && log "Pointed $n setup file(s) at your home instead of the hidden session's"
  true
}

hook_block() {
  cat <<'EOF'
# >>> kali-looks >>> (gives each login-screen look its own settings; remove with: looks sessions remove)
if [ -x "$HOME/.local/bin/looks" ]; then
  _looks_cfg=$("$HOME/.local/bin/looks" session-hook "${DESKTOP_SESSION:-}" 2>/dev/null) || _looks_cfg=
  if [ -n "$_looks_cfg" ] && [ -d "$_looks_cfg" ]; then export XDG_CONFIG_HOME="$_looks_cfg"; fi
  unset _looks_cfg
elif [ -L "$HOME/.config" ] && [ -d "$HOME/.local/share/kali-looks/config/base" ]; then
  # the looks command is missing (repo moved?): fall back to your own settings
  ln -sfn "$HOME/.local/share/kali-looks/config/base" "$HOME/.config.kali-looks" \
    && mv -Tf "$HOME/.config.kali-looks" "$HOME/.config"
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
    # Hidden from the login screen: AeroThemePlasma's own entries (ours replace them),
    # and the plain Plasma and Wayland sessions, which skip ~/.xsessionrc and so would
    # run on whichever look's settings were used last.
    echo "for f in $HIDDEN_SESSIONS; do"
    echo '  if [ -f "$f" ] && ! grep -q "^NoDisplay=true" "$f"; then echo "NoDisplay=true # kali-looks" >> "$f"; fi; done'
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
  [[ $(current_look) == base ]] || die "Log into your own Kali desktop first (you're in $(current_look))."
  script=$(mktemp)
  {
    echo 'rm -f /usr/share/xsessions/kali-looks-*.desktop'
    echo "for f in $HIDDEN_SESSIONS; do"
    echo '  if [ -f "$f" ]; then sed -i "/^NoDisplay=true\( # kali-looks\)\?$/d" "$f"; fi; done'
  } > "$script"
  as_root bash "$script" || warn "Couldn't remove the session files."
  rm -f "$script"
  strip_marked "$XSESSIONRC"
  rm -f "$LOCAL_SHARE/applications/kali-looks-switch.desktop"
  if [[ -L $HOME/.config && -d $BASE_CFG ]]; then
    swap_home_files base base
    rm -f "$HOME/.config" && mv -T "$BASE_CFG" "$HOME/.config"
    for d in "$CFG_ROOT"/*/; do find "$d" -maxdepth 1 -type l -lname "$BASE_CFG/*" -delete 2>/dev/null || true; done
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
sandbox_runtime() { echo "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/kali-looks-sandbox-$1"; }
sandbox_display() { case $1 in macos) echo :5 ;; winxp) echo :6 ;; win7) echo :7 ;; *) echo :8 ;; esac; }

session_lang() {
  local l=${LANG:-}
  [[ -z $l || $l == C || $l == POSIX ]] && l=$(sed -n 's/^LANG=//p' /etc/default/locale 2>/dev/null | tr -d '"')
  echo "${l:-C.UTF-8}"
}

sandbox_env() { # prints KEY=VALUE lines
  local look=$1 h rt d
  h=$(sandbox_home "$look"); rt=$(sandbox_runtime "$look"); d=$(sandbox_display "$look")
  printf '%s\n' "HOME=$h" "DISPLAY=$d" "XDG_RUNTIME_DIR=$rt" "XDG_SESSION_TYPE=x11" \
    "XDG_CURRENT_DESKTOP=KDE" "XDG_SESSION_DESKTOP=KDE" "KDE_FULL_SESSION=true" "KDE_SESSION_VERSION=6" \
    "DESKTOP_SESSION=kali-looks-$look" "LANG=$(session_lang)" \
    "PATH=$HERE/lib/sandbox-bin:$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    "USER=$USER" "LOGNAME=$USER" "SHELL=/bin/bash" "XDG_CONFIG_HOME=$CFG_ROOT/$look" \
    "XAUTHORITY=$rt/Xauthority"
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
  # pointer/GTK 2 files written there land in your home, and are filed under the look at stop
  ln -sfn "$HOME/.gtkrc-2.0" "$h/.gtkrc-2.0"
  # (screenshots for the README use an empty desktop)
  if [[ -n ${SANDBOX_DESKTOP:-} ]]; then mkdir -p "$SANDBOX_DESKTOP"; ln -sfn "$SANDBOX_DESKTOP" "$h/Desktop"; fi
  true
}

sandbox_bus() {
  local look=$1 p d
  d=$(sandbox_display "$look")
  for p in $(pgrep -u "$(id -u)" -x plasmashell); do
    if { tr '\0' '\n' < "/proc/$p/environ"; } 2>/dev/null | grep -qx "DISPLAY=$d"; then
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
      if pgrep -f "Xvfb $d " >/dev/null; then die "A hidden $look session is already running (looks sandbox $look stop)."; fi
      sandbox_prepare "$look"
      mkdir -p "$rt" "$DATA_DIR/sandbox/$look"; chmod 700 "$rt"
      # The look's pointer/GTK 2 files are the ones in your home while it runs here
      swap_home_files "$(current_look)" "$look"
      # Don't bring back apps from the look's last real session (they'd share your
      # browser profiles etc. on the hidden screen)
      if command -v kwriteconfig6 >/dev/null; then
        local lm; lm=$(kreadconfig6 --file "$CFG_ROOT/$look/ksmserverrc" --group General --key loginMode 2>/dev/null || true)
        echo "${lm:-unset}" > "$DATA_DIR/sandbox/$look/loginMode"
        kwriteconfig6 --file "$CFG_ROOT/$look/ksmserverrc" --group General --key loginMode emptySession
      fi
      local -a xauth=()
      rm -f "$rt/Xauthority"; touch "$rt/Xauthority"; chmod 600 "$rt/Xauthority"
      if command -v xauth >/dev/null && xauth -q -f "$rt/Xauthority" add "$d" . "$(mcookie 2>/dev/null || od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"; then
        xauth=(-auth "$rt/Xauthority")
      fi
      setsid Xvfb "$d" -screen 0 "${SANDBOX_SIZE:-1920x1080}x24" +extension GLX -nolisten tcp \
        "${xauth[@]}" >"$DATA_DIR/sandbox/$look/xvfb.log" 2>&1 < /dev/null &
      sleep 2
      cmd=$(session_field "$look" 3 2>/dev/null || echo startplasma-x11)
      mapfile -t env_kv < <(sandbox_env "$look")
      # In its own scope, outside your login session: otherwise locking your screen
      # (or the laptop sleeping) would lock the hidden session too.
      local -a scope=()
      if systemd-run --user --scope --quiet true 2>/dev/null; then
        scope=(systemd-run --user --scope --quiet --collect --unit="kali-looks-sandbox-$look-$$")
      fi
      # The desktop gets a stand-in system bus without logind: otherwise its screen
      # locker follows your real session's lock state and locks the hidden one too.
      local -a bus=()
      if [[ -s $DATA_DIR/sandbox/$look/sysbus.pid ]]; then kill "$(cat "$DATA_DIR/sandbox/$look/sysbus.pid")" 2>/dev/null || true; fi
      mapfile -t bus < <(dbus-daemon --session --fork --print-address=1 --print-pid=1 --nopidfile 2>/dev/null)
      if [[ -n ${bus[0]:-} ]]; then
        env_kv+=("DBUS_SYSTEM_BUS_ADDRESS=${bus[0]}")
        echo "${bus[1]:-}" > "$DATA_DIR/sandbox/$look/sysbus.pid"
      fi
      setsid "${scope[@]}" env -i "${env_kv[@]}" dbus-run-session "$cmd" >"$log" 2>&1 < /dev/null &
      for i in $(seq 60); do sandbox_bus "$look" >/dev/null && break; sleep 1; done
      sandbox_bus "$look" >/dev/null || die "The hidden $look session didn't start (see $log)."
      ok "Hidden $look session running on $d" ;;
    stop)
      for p in $(pgrep -u "$(id -u)"); do
        if { tr '\0' '\n' < "/proc/$p/environ"; } 2>/dev/null | grep -qx "DISPLAY=$d"; then kill "$p" 2>/dev/null || true; fi
      done
      sleep 2; pkill -f "Xvfb $d " || true
      if [[ -s $DATA_DIR/sandbox/$look/sysbus.pid ]]; then kill "$(cat "$DATA_DIR/sandbox/$look/sysbus.pid")" 2>/dev/null || true; rm -f "$DATA_DIR/sandbox/$look/sysbus.pid"; fi
      if [[ -f $DATA_DIR/sandbox/$look/loginMode ]]; then
        local lm; lm=$(cat "$DATA_DIR/sandbox/$look/loginMode"); rm -f "$DATA_DIR/sandbox/$look/loginMode"
        if ! command -v kwriteconfig6 >/dev/null; then :
        elif [[ $lm == unset ]]; then kwriteconfig6 --file "$CFG_ROOT/$look/ksmserverrc" --group General --key loginMode --delete
        else kwriteconfig6 --file "$CFG_ROOT/$look/ksmserverrc" --group General --key loginMode "$lm"; fi
        swap_home_files "$look" "$(current_look)"
      fi
      ok "Hidden $look session stopped" ;;
    shot)
      mkdir -p "$DATA_DIR/sandbox/$look/shots"
      DISPLAY=$d XAUTHORITY="$rt/Xauthority" import -window root "$DATA_DIR/sandbox/$look/shots/${3:-shot}.png"
      echo "$DATA_DIR/sandbox/$look/shots/${3:-shot}.png" ;;
    run)
      shift 2
      mapfile -t env_kv < <(sandbox_env "$look")
      env -i "${env_kv[@]}" DBUS_SESSION_BUS_ADDRESS="$(sandbox_bus "$look")" "$@" ;;
    *) die "usage: looks sandbox <look> start|stop|shot NAME|run CMD..." ;;
  esac
}
