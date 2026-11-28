#!/usr/bin/env bash
# cupertino-xfce: make Xfce (Kali / Debian 13) look and feel like macOS.
# Global menu bar, frosted dock, Control Center, Spotlight, Launchpad, Mission Control,
# blur and rounded corners, Mac shortcuts, login screen, boot splash, light and dark mode.
#
#   ./install.sh            light mode (default)
#   ./install.sh --dark     dark mode
#   ./install.sh --help     all options
#
# Everything it changes is backed up first. Undo with ./uninstall.sh
set -Eeuo pipefail

VERSION="0.1.0"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

# ---- pinned upstream versions (the versions this release was tested with) -------------
WHITESUR_GTK_URL="https://github.com/vinceliuice/WhiteSur-gtk-theme.git"
WHITESUR_GTK_COMMIT="d5782652d412137e26fb8ff55b55a5572e4c6995"
WHITESUR_ICON_URL="https://github.com/vinceliuice/WhiteSur-icon-theme.git"
WHITESUR_ICON_COMMIT="73d8040da51a9ed74e47c7366e7e9ff437601a5c"
WHITESUR_CURSOR_URL="https://github.com/vinceliuice/WhiteSur-cursors.git"
WHITESUR_CURSOR_COMMIT="e190baf618ed95ee217d2fd45589bd309b37672b"
WHITESUR_FIREFOX_URL="https://github.com/vinceliuice/WhiteSur-firefox-theme.git"
WHITESUR_FIREFOX_COMMIT="ecc6465e2d30278a0f76604e622e3df8ac08ae1c"
SHA_WHITESUR_LIGHT="2635570e218afab2d34b0663287054f7b995b9f7f810e97410dcad389987d5ba"
SHA_WHITESUR_DARK="98ac7545ec5290b718875fdfbdd7f0f6b88126103d1eec259ec9fbf80be7b75f"

# Global-menu plugin. Used only when your distro doesn't package xfce4-appmenu-plugin
# (Kali doesn't). Fetched from Debian's permanent snapshot archive and checksum-verified.
# Format: "<file> <sha1> <sha256>"
APPMENU_DEBS=(
  "vala-panel-appmenu-common_25.04+dfsg-3_all.deb 9d120e88006e355f528ef21f7655f84563b007a7 bffb68f66a2dd1c790448fd076658e45d5a36a59c4a3e80dad97c95643403b2c"
  "xfce4-appmenu-plugin_25.04+dfsg-3_amd64.deb b8c9702b4829a39610001921f6827ee10f19821b 0508ee60eccc2839d6fa42a2952ddd661dad7a6079c8101ec97c55041e4c85b7"
)

# Dock with macOS-style magnification: Plank Reloaded, from its author's Debian repo
# (https://github.com/zquestz/plank-reloaded), checksum-pinned. Format: "<arch> <file> <sha256>"
PLANK_REPO="https://zquestz.github.io/ppa/debian"
PLANK_DEBS=(
  "amd64 plank-reloaded-debian_0.11.178-1_amd64.deb aaa055faffda483b64f24e1f130fc039f99f18da87c6c3c30210c748e0c8d3e6"
  "arm64 plank-reloaded-debian_0.11.178-1_arm64.deb bea8743bffbf924740240e4e59d578028b099cceba6b491f0689ccd24f689465"
)

PACKAGES=(git curl xz-utils bzip2 x11-xserver-utils dconf-cli xdg-user-dirs picom rofi fonts-inter fonts-jetbrains-mono
          python3-gi gir1.2-gtk-3.0 xfce4-panel-profiles xfce4-docklike-plugin xfce4-whiskermenu-plugin
          xfce4-pulseaudio-plugin xfce4-notifyd xfce4-power-manager-plugins xfce4-screenshooter)
APPMENU_PACKAGES=(appmenu-registrar appmenu-gtk3-module gir1.2-wnck-3.0 xdotool wmctrl x11-utils)

# ---- options --------------------------------------------------------------------------
MODE="light"; DOCK="plank"; DO_LOGIN=1; DO_GLOBAL_MENU=1; DO_EFFECTS=1; DO_BOOT=1; DO_FIREFOX=1; DO_TERMINAL=1
DRY_RUN=0; ASSUME_YES=0

usage() {
  cat <<EOF
cupertino-xfce $VERSION: macOS look and feel for Xfce

Usage: ./install.sh [options]

  --light            Light mode (default)
  --dark             Dark mode (switch any time with: cupertino-xfce-mode toggle)
  --docklike         Use Xfce's Docklike panel as the dock (no magnification) instead of Plank
  --no-global-menu   Skip the File/Edit/View menu bar
  --no-effects       Skip picom (blur, rounded corners, shadows)
  --no-login         Leave the login screen alone
  --no-boot-splash   Leave the boot splash alone
  --no-firefox       Leave Firefox's look alone
  --no-terminal      Leave QTerminal's colours and font alone
  --dry-run          Check your system and show what would change, then stop
  -y, --yes          Don't ask for confirmation
  -h, --help         Show this help

Set CUPERTINO_ROOT=pkexec to get a graphical password prompt instead of sudo.
EOF
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --light) MODE=light ;;
    --dark) MODE=dark ;;
    --docklike) DOCK=docklike ;;
    --no-global-menu) DO_GLOBAL_MENU=0 ;;
    --no-effects) DO_EFFECTS=0 ;;
    --no-login) DO_LOGIN=0 ;;
    --no-boot-splash) DO_BOOT=0 ;;
    --no-firefox) DO_FIREFOX=0 ;;
    --no-terminal) DO_TERMINAL=0 ;;
    --dry-run) DRY_RUN=1 ;;
    -y|--yes) ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
  shift
done

APP_DIR="$DATA_DIR/app"                       # self-contained copy used by the mode switcher
BIN_DIR="$HOME/.local/bin"
WALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/backgrounds/cupertino-xfce"
ICON_DST="${XDG_DATA_HOME:-$HOME/.local/share}/icons"
QT_INI="${XDG_CONFIG_HOME:-$HOME/.config}/qterminal.org/qterminal.ini"
GTK_SETTINGS_INI="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini"
ONCE_AUTOSTART="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/cupertino-xfce-once.desktop"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/$STAMP"

# ---- helpers -------------------------------------------------------------------------
apt_has() { apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/{print $2}' | grep -qv '(none)'; }
pkg_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"; }

# Record a property's current value once per run (for uninstall), optionally set it.
declare -A RECORDED=()
record_prop() {
  local ch=$1 prop=$2 type=$3 cur
  [[ -z ${RECORDED["$ch|$prop"]:-} ]] || return 0
  if cur=$(xfconf-query -c "$ch" -p "$prop" 2>/dev/null); then
    printf '%s\t%s\t%s\t1\t%s\n' "$ch" "$prop" "$type" "$cur" >> "$BACKUP_DIR/xfconf.tsv"
  else
    printf '%s\t%s\t%s\t0\t\n' "$ch" "$prop" "$type" >> "$BACKUP_DIR/xfconf.tsv"
  fi
  RECORDED["$ch|$prop"]=1
}
apply_prop() { record_prop "$1" "$2" "$3"; xset_prop "$1" "$2" "$3" "$4"; }

# Same idea for INI files (qterminal.ini, gtk-3.0/settings.ini).
apply_ini() {
  local file=$1 section=$2 key=$3 val=$4 cur existed=0
  if cur=$(python3 "$HERE/lib/ini-set.py" "$file" "$section" "$key" --get 2>/dev/null); then existed=1; fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$file" "$section" "$key" "$existed" "${cur:-}" >> "$BACKUP_DIR/ini.tsv"
  python3 "$HERE/lib/ini-set.py" "$file" "$section" "$key" "$val" >/dev/null
}

# Fetch one pinned commit of a git repo into $SRC_DIR/<name>.
fetch_repo() {
  local url=$2 commit=$3 dir="$SRC_DIR/$1"
  if [[ -d $dir/.git ]] && [[ $(git -C "$dir" rev-parse HEAD 2>/dev/null) == "$commit" ]]; then
    return 0
  fi
  rm -rf "$dir"; mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" remote add origin "$url"
  git -C "$dir" fetch -q --depth 1 origin "$commit"
  git -C "$dir" checkout -q FETCH_HEAD
}

sha_ok() { echo "$2  $1" | sha256sum -c --status; }

# Connected monitors: primary first. Output names only.
monitors() {
  xrandr --listmonitors 2>/dev/null | awk 'NR > 1 { name = $2; prim = (name ~ /\*/); gsub(/^[+*]+/, "", name); print (prim ? 0 : 1), name }' \
    | sort -s -n -k1,1 | cut -d' ' -f2
}

find_desktop() {
  local id dir
  for id in "$@"; do
    for dir in "${XDG_DATA_HOME:-$HOME/.local/share}/applications" /usr/local/share/applications /usr/share/applications /var/lib/flatpak/exports/share/applications; do
      if [[ -f $dir/$id ]]; then printf '%s\n' "$dir/$id"; return 0; fi
    done
  done
  return 1
}

firefox_profiles() {
  local d
  for d in "$HOME"/.mozilla/firefox/*/; do
    [[ -f $d/prefs.js ]] && printf '%s\n' "${d%/}"
  done
  return 0
}

# ---- preflight ------------------------------------------------------------------------
require_xfce_session
ARCH=$(dpkg --print-architecture)
USE_LIGHTDM_GTK=0
if [[ $DO_LOGIN -eq 1 && -f $GREETER_CONF ]] && pkg_installed lightdm-gtk-greeter; then USE_LIGHTDM_GTK=1; fi
if [[ $DO_BOOT -eq 1 ]]; then
  if ! pkg_installed plymouth || ! grep -qw splash /proc/cmdline; then DO_BOOT=0; BOOT_WHY="Plymouth isn't active"; fi
fi
# The boot splash draws its status line and password prompt as text, which needs
# Plymouth's text renderer; without it plymouthd crashes on the first message.
BOOT_PACKAGES=()
if [[ $DO_BOOT -eq 1 ]] && [[ ! -e /usr/lib/$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo x86_64-linux-gnu)/plymouth/label-pango.so ]]; then
  if apt_has plymouth-label; then BOOT_PACKAGES=(plymouth-label)
  else DO_BOOT=0; BOOT_WHY="Plymouth's text renderer (plymouth-label) isn't available"; fi
fi
QTW_DIR=""
for d in /usr/share/qtermwidget6 /usr/share/qtermwidget5; do [[ -d $d/color-schemes ]] && { QTW_DIR=$d/color-schemes; break; }; done
[[ $DO_TERMINAL -eq 1 && ( -z $QTW_DIR || ! -f $QT_INI ) ]] && { DO_TERMINAL=0; TERM_WHY="QTerminal not found"; }
mapfile -t FF_PROFILES < <(firefox_profiles)
[[ $DO_FIREFOX -eq 1 && ${#FF_PROFILES[@]} -eq 0 ]] && { DO_FIREFOX=0; FF_WHY="no Firefox profile"; }

APPMENU_SOURCE="none"
if [[ $DO_GLOBAL_MENU -eq 1 ]]; then
  if pkg_installed xfce4-appmenu-plugin; then APPMENU_SOURCE="installed"
  elif apt_has xfce4-appmenu-plugin; then APPMENU_SOURCE="apt"
  elif [[ $ARCH == amd64 ]] && apt_has appmenu-registrar; then APPMENU_SOURCE="debian-snapshot"
  else warn "No global-menu plugin available for this system ($ARCH); skipping the File/Edit/View menu bar."; DO_GLOBAL_MENU=0
  fi
fi

PLANK_SOURCE="none"; PLANK_FILE=""; PLANK_SHA=""
if [[ $DOCK == plank ]]; then
  if pkg_installed plank-reloaded; then PLANK_SOURCE="installed"
  elif pkg_installed plank; then
    warn "The original 'plank' package is installed and conflicts with Plank Reloaded; using the Docklike dock."; DOCK=docklike
  elif apt_has plank-reloaded; then PLANK_SOURCE="apt"
  else
    for entry in "${PLANK_DEBS[@]}"; do
      read -r a f h <<<"$entry"
      if [[ $a == "$ARCH" ]]; then PLANK_SOURCE="author-repo"; PLANK_FILE=$f; PLANK_SHA=$h; fi
    done
    if [[ $PLANK_SOURCE == none ]]; then warn "No Plank Reloaded build for $ARCH; using the Docklike dock."; DOCK=docklike; fi
  fi
fi

MISSING=()
for p in "${PACKAGES[@]}" "${BOOT_PACKAGES[@]}"; do pkg_installed "$p" || MISSING+=("$p"); done
if [[ $DO_GLOBAL_MENU -eq 1 ]]; then
  for p in "${APPMENU_PACKAGES[@]}"; do pkg_installed "$p" || MISSING+=("$p"); done
  [[ $APPMENU_SOURCE == apt ]] && MISSING+=(xfce4-appmenu-plugin)
fi
[[ $PLANK_SOURCE == apt ]] && MISSING+=(plank-reloaded)

mapfile -t MONITORS < <(monitors)
[[ ${#MONITORS[@]} -gt 0 ]] || MONITORS=("")
yn() { [[ $1 -eq 1 ]] && echo "yes${2:+ ($2)}" || echo "no${3:+ ($3)}"; }

cat <<EOF

${C_BLUE}cupertino-xfce $VERSION${C_OFF}: $MODE mode
  Packages to install: ${MISSING[*]:-none}
  Dock:                $([[ $DOCK == plank ]] && echo "Plank Reloaded, magnifies on hover ($PLANK_SOURCE${PLANK_FILE:+: $PLANK_FILE, checksum-pinned, from its author repo})" || echo "Docklike (no magnification)")
  Global menu bar:     $(yn "$DO_GLOBAL_MENU" "$APPMENU_SOURCE")
  Blur/rounded/shadow: $(yn "$DO_EFFECTS" "picom replaces Xfce's compositor")
  Login screen:        $(yn "$USE_LIGHTDM_GTK" "" "needs the LightDM GTK greeter")
  Boot splash:         $(yn "$DO_BOOT" "rebuilds your initramfs, ~1 min" "${BOOT_WHY:-}")
  Firefox look:        $(yn "$DO_FIREFOX" "applies next time Firefox starts" "${FF_WHY:-}")
  Terminal colours:    $(yn "$DO_TERMINAL" "" "${TERM_WHY:-}")
  Monitors:            ${MONITORS[*]:-unknown} (a menu bar on each)
  Backup goes to:      $BACKUP_DIR

EOF

if [[ $DRY_RUN -eq 1 ]]; then ok "Dry run: nothing was changed."; exit 0; fi
if [[ $ASSUME_YES -eq 0 ]]; then
  if [[ -t 0 ]]; then
    read -rp "Apply it? Running apps may need a restart to pick up the menu bar. [y/N] " ans
    [[ $ans =~ ^[Yy] ]] || { echo "Cancelled."; exit 0; }
  else
    die "No terminal to confirm in. Re-run with --yes to proceed."
  fi
fi

mkdir -p "$BACKUP_DIR" "$SRC_DIR" "$CONF_DIR" "$BIN_DIR"
printf 'version=%s\nmode=%s\ndate=%s\n' "$VERSION" "$MODE" "$STAMP" > "$BACKUP_DIR/info"
: > "$BACKUP_DIR/xfconf.tsv"; : > "$BACKUP_DIR/ini.tsv"

# ---- 1. packages (root) -------------------------------------------------------------
if [[ ${#MISSING[@]} -gt 0 || $APPMENU_SOURCE == debian-snapshot || $PLANK_SOURCE == author-repo ]]; then
  DEB_PATHS=()
  if [[ $PLANK_SOURCE == author-repo ]]; then
    log "Downloading Plank Reloaded from its author's repo"
    mkdir -p "$SRC_DIR/debs"
    if [[ ! -f $SRC_DIR/debs/$PLANK_FILE ]] || ! sha_ok "$SRC_DIR/debs/$PLANK_FILE" "$PLANK_SHA"; then
      if ! curl -fsSL -o "$SRC_DIR/debs/$PLANK_FILE" "$PLANK_REPO/$PLANK_FILE"; then
        # The pinned build was pruned: take the newest one for this arch from the repo index.
        idx=$(curl -fsSL "$PLANK_REPO/Packages") || die "Can't reach $PLANK_REPO"
        read -r PLANK_FILE PLANK_SHA < <(awk -v a="$ARCH" '/^Version:/{v=$2} /^Architecture:/{ar=$2} /^Filename:/{f=$2} /^SHA256:/{if (ar==a) {sub(/^\.\//,"",f); print v, f, $2}}' <<<"$idx" | sort -V | tail -n 1 | cut -d' ' -f2-)
        [[ -n $PLANK_FILE ]] || die "No Plank Reloaded build for $ARCH in $PLANK_REPO"
        curl -fsSL -o "$SRC_DIR/debs/$PLANK_FILE" "$PLANK_REPO/$PLANK_FILE"
      fi
    fi
    sha_ok "$SRC_DIR/debs/$PLANK_FILE" "$PLANK_SHA" || die "Checksum mismatch for $PLANK_FILE; refusing to install it."
    DEB_PATHS+=("$SRC_DIR/debs/$PLANK_FILE")
    ok "Verified $PLANK_FILE"
  fi
  if [[ $APPMENU_SOURCE == debian-snapshot ]]; then
    log "Downloading the global-menu plugin from Debian's archive"
    mkdir -p "$SRC_DIR/debs"
    for entry in "${APPMENU_DEBS[@]}"; do
      read -r f sha1 sha256 <<<"$entry"
      if [[ ! -f $SRC_DIR/debs/$f ]] || ! sha_ok "$SRC_DIR/debs/$f" "$sha256"; then
        curl -fsSL -o "$SRC_DIR/debs/$f" "https://snapshot.debian.org/file/$sha1"
      fi
      sha_ok "$SRC_DIR/debs/$f" "$sha256" || die "Checksum mismatch for $f; refusing to install it."
      DEB_PATHS+=("$SRC_DIR/debs/$f")
    done
    ok "Verified ${#DEB_PATHS[@]} packages"
  fi
  printf '%s\n' "${MISSING[@]}" > "$BACKUP_DIR/packages-added.txt"
  [[ $APPMENU_SOURCE == debian-snapshot ]] && printf '%s\n' xfce4-appmenu-plugin vala-panel-appmenu-common >> "$BACKUP_DIR/packages-added.txt"
  [[ $PLANK_SOURCE == author-repo ]] && echo plank-reloaded >> "$BACKUP_DIR/packages-added.txt"
  log "Installing packages (you'll be asked for your password)"
  ROOT1="$BACKUP_DIR/root-packages.sh"
  {
    echo "set -e"
    echo "export DEBIAN_FRONTEND=noninteractive"
    echo "apt-get update -qq"
    printf 'apt-get install -y --no-upgrade'; printf ' %q' "${MISSING[@]}" "${DEB_PATHS[@]}"; echo
  } > "$ROOT1"
  as_root_script "$ROOT1"
  ok "Packages installed"
fi

# ---- 2. backup ----------------------------------------------------------------------
log "Backing up your current setup"
xfce4-panel-profiles save "$BACKUP_DIR/panel.tar.bz2" >/dev/null 2>&1 || warn "Couldn't save your panel layout (xfce4-panel-profiles)."
[[ -f $GTK_CSS ]] && cp -a "$GTK_CSS" "$BACKUP_DIR/gtk.css"
cp -a "${XDG_CONFIG_HOME:-$HOME/.config}/xfce4/xfconf/xfce-perchannel-xml" "$BACKUP_DIR/xfconf-xml" 2>/dev/null || true
[[ -f $QT_INI ]] && cp -a "$QT_INI" "$BACKUP_DIR/qterminal.ini"
if command -v dconf >/dev/null; then dconf dump /net/launchpad/plank/ > "$BACKUP_DIR/plank.dconf" 2>/dev/null || true; fi
ok "Saved to $BACKUP_DIR"

# ---- 3. self-contained app copy + helper commands ------------------------------------
rm -rf "$APP_DIR"; mkdir -p "$APP_DIR"
cp -a "$HERE/lib" "$HERE/config" "$HERE/apps" "$APP_DIR/"
chmod +x "$APP_DIR/lib/mode.sh" "$APP_DIR/apps/cupertino-control-center" "$APP_DIR/apps/cupertino-menud"
ln -sf "$APP_DIR/lib/mode.sh" "$BIN_DIR/cupertino-xfce-mode"
ln -sf "$APP_DIR/apps/cupertino-control-center" "$BIN_DIR/cupertino-control-center"
ln -sf "$APP_DIR/apps/cupertino-menud" "$BIN_DIR/cupertino-menud"
# shellcheck source=lib/mode.sh
source "$APP_DIR/lib/mode.sh"

# ---- 4. WhiteSur theme, icons and cursors (from upstream, pinned) ---------------------
log "Fetching WhiteSur theme, icons and cursors"
fetch_repo WhiteSur-gtk-theme "$WHITESUR_GTK_URL" "$WHITESUR_GTK_COMMIT"
fetch_repo WhiteSur-icon-theme "$WHITESUR_ICON_URL" "$WHITESUR_ICON_COMMIT"
fetch_repo WhiteSur-cursors "$WHITESUR_CURSOR_URL" "$WHITESUR_CURSOR_COMMIT"
REL="$SRC_DIR/WhiteSur-gtk-theme/release"
sha_ok "$REL/WhiteSur-Light.tar.xz" "$SHA_WHITESUR_LIGHT" || die "WhiteSur-Light archive checksum mismatch."
sha_ok "$REL/WhiteSur-Dark.tar.xz" "$SHA_WHITESUR_DARK" || die "WhiteSur-Dark archive checksum mismatch."

mkdir -p "$HOME/.themes" "$HOME/.icons" "$ICON_DST"
rm -rf "$HOME/.themes/WhiteSur-Light" "$HOME/.themes/WhiteSur-Dark"
tar -xJf "$REL/WhiteSur-Light.tar.xz" -C "$HOME/.themes"
tar -xJf "$REL/WhiteSur-Dark.tar.xz" -C "$HOME/.themes"

# Icons: the base set (light status icons, for dark bars) and a -light set (dark status
# icons, for light bars). Mirrors what upstream's install.sh does, without running it.
ICON_SRC="$SRC_DIR/WhiteSur-icon-theme"
T="$ICON_DST/WhiteSur"; rm -rf "$T"; mkdir -p "$T/status"
cp "$ICON_SRC/src/index.theme" "$T/"
cp -r "$ICON_SRC"/src/{actions,animations,apps,categories,devices,emotes,emblems,mimes,places,preferences} "$T/"
cp -r "$ICON_SRC"/src/status/{16,22,24,32,symbolic} "$T/status/"
rm -f "$T"/places/scalable/user-trash{,-full}-dark.svg
cp -r "$ICON_SRC"/links/{actions,apps,categories,devices,emotes,emblems,mimes,places,status,preferences} "$T/"
L="$ICON_DST/WhiteSur-light"; rm -rf "$L"; mkdir -p "$L/status"
sed 's/WhiteSur/WhiteSur-light/g' "$ICON_SRC/src/index.theme" > "$L/index.theme"
cp -r "$ICON_SRC"/src/status/{16,22,24,32} "$L/status/"
find "$L/status" -type f -name '*.svg' -exec sed -i 's/#f2f2f2/#363636/g' {} +
cp -r "$ICON_SRC"/links/status/{16,22,24,32} "$L/status/"
for d in actions animations apps categories devices emotes emblems mimes places preferences; do ln -s "../WhiteSur/$d" "$L/$d"; done
ln -s ../../WhiteSur/status/symbolic "$L/status/symbolic"
gtk-update-icon-cache -q "$T" 2>/dev/null || true
gtk-update-icon-cache -q "$L" 2>/dev/null || true

# Control Center's menu-bar icon (symbolic, so it follows the bar's text colour)
install -Dm644 "$HERE/config/icons/cupertino-control-center-symbolic.svg" \
  "$ICON_DST/hicolor/scalable/apps/cupertino-control-center-symbolic.svg"
gtk-update-icon-cache -q "$ICON_DST/hicolor" 2>/dev/null || true

rm -rf "$HOME/.icons/WhiteSur-cursors"
cp -r "$SRC_DIR/WhiteSur-cursors/dist" "$HOME/.icons/WhiteSur-cursors"
ok "Theme, icons and cursors installed"

# ---- 5. wallpapers -----------------------------------------------------------------
mkdir -p "$WALL_DIR"
cp "$HERE"/wallpapers/*.jpg "$WALL_DIR/"
WS_COUNT=$(xfconf-query -c xfwm4 -p /general/workspace_count 2>/dev/null || echo 1)
for m in "${MONITORS[@]}"; do
  [[ -n $m ]] || continue
  for ((w = 0; w < WS_COUNT; w++)); do
    k="/backdrop/screen0/monitor$m/workspace$w/last-image"
    record_prop xfce4-desktop "$k" string
    xfconf-query -c xfce4-desktop -p "$k" >/dev/null 2>&1 || xset_prop xfce4-desktop "$k" string "$WALL_DIR/blue-waves.jpg"
  done
done
while IFS= read -r k; do
  record_prop xfce4-desktop "$k" string
  apply_prop xfce4-desktop "${k%last-image}image-style" int 5
done < <(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep -E '/workspace[0-9]+/last-image$' || true)

# ---- 6. settings that don't depend on light/dark --------------------------------------
log "Applying fonts, cursors, window buttons and shortcuts"
record_prop xsettings /Net/ThemeName string
record_prop xsettings /Net/IconThemeName string
record_prop xfwm4 /general/theme string
record_prop xfce4-notifyd /theme string
apply_prop xsettings /Gtk/CursorThemeName string WhiteSur-cursors
apply_prop xsettings /Gtk/FontName string "Inter 10"
apply_prop xfwm4 /general/button_layout string "CHM|"
apply_prop xfwm4 /general/title_font string "Inter Semi-Bold 10"
apply_prop xfwm4 /general/title_alignment string center
apply_prop xfce4-notifyd /notify-location uint 2
apply_prop xfce4-notifyd /initial-opacity double 1.0
# Hide underlined shortcut letters in menus (Alt still opens menus in apps).
apply_ini "$GTK_SETTINGS_INI" Settings gtk-enable-mnemonics false

KS=xfce4-keyboard-shortcuts
apply_prop $KS "/commands/custom/<Super>space" string "rofi -show drun -theme $CONF_DIR/rofi/spotlight.rasi"
apply_prop $KS "/commands/custom/<Primary>Up" string "rofi -show window -theme $CONF_DIR/rofi/missioncontrol.rasi"
apply_prop $KS "/xfwm4/custom/<Super>q" string close_window_key
apply_prop $KS "/xfwm4/custom/<Super>Tab" string cycle_windows_key
apply_prop $KS "/xfwm4/custom/<Shift><Super>Tab" string cycle_reverse_windows_key
apply_prop $KS "/commands/custom/<Primary><Super>q" string xflock4
# Super+Shift+3 / 4 / 5: full screen, area, screenshot tool. Saved straight to the Desktop
# as "Screenshot 2026-11-23 at 4.08.33 PM.png", like macOS. (Given only a folder,
# xfce4-screenshooter opens a Save dialog instead, so build the full name at run time.)
# Xfce may store either the shifted keysym or the digit, so register both.
# shellcheck disable=SC2016  # expanded later by sh -c when the shortcut runs
SHOT_NAME='"$(xdg-user-dir DESKTOP)/Screenshot $(date +"%Y-%m-%d at %-I.%M.%S %p").png"'
for k in "<Shift><Super>numbersign" "<Shift><Super>3"; do apply_prop $KS "/commands/custom/$k" string "sh -c 'xfce4-screenshooter -f -s $SHOT_NAME'"; done
for k in "<Shift><Super>dollar" "<Shift><Super>4"; do apply_prop $KS "/commands/custom/$k" string "sh -c 'xfce4-screenshooter -r -s $SHOT_NAME'"; done
for k in "<Shift><Super>percent" "<Shift><Super>5"; do apply_prop $KS "/commands/custom/$k" string "xfce4-screenshooter"; done

mkdir -p "$(dirname "$LAUNCHPAD_DESKTOP")"
cat > "$LAUNCHPAD_DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Launchpad
Comment=Show all apps
Exec=rofi -show drun -theme $CONF_DIR/rofi/launchpad.rasi
Icon=view-app-grid
Categories=Utility;
EOF
# Give the desktop an app name, so the menu bar says "Finder" instead of "xfdesktop"
# when the wallpaper has focus. Hidden from app launchers.
for f in org.xfce.xfdesktop.desktop xfdesktop.desktop; do
  dst="$(dirname "$LAUNCHPAD_DESKTOP")/$f"
  [[ -e "$dst" ]] && ! grep -q 'X-Cupertino-Xfce=true' "$dst" && continue
  cat > "$dst" <<'EOF'
[Desktop Entry]
Type=Application
Name=Finder
Comment=Desktop
Exec=thunar
Icon=system-file-manager
StartupWMClass=xfdesktop
NoDisplay=true
X-Cupertino-Xfce=true
EOF
done
ok "Inter font · Super+Space Spotlight · Ctrl+Up Mission Control · Super+Q · Super+Shift+3/4/5"

# ---- 7. global menu ------------------------------------------------------------------
if [[ $DO_GLOBAL_MENU -eq 1 ]]; then
  log "Turning on the global menu"
  apply_prop xsettings /Gtk/ShellShowsMenubar bool true
  apply_prop xsettings /Gtk/ShellShowsAppmenu bool true
  mods=$(xfconf-query -c xsettings -p /Gtk/Modules 2>/dev/null || true)
  if [[ ":$mods:" != *":appmenu-gtk-module:"* ]]; then
    apply_prop xsettings /Gtk/Modules string "${mods:+$mods:}appmenu-gtk-module"
  fi
  ok "Apps send their menus to the menu bar (restart running apps to see it)"
fi

# ---- 8. panels: a menu bar on every monitor + the dock ---------------------------------
log "Building the menu bar, Control Center and dock"
mode_vars "$MODE"
PDIR=$(mktemp -d)
BAR_RGBA_GV="[<${BAR_RGBA[0]}>, <${BAR_RGBA[1]}>, <${BAR_RGBA[2]}>, <${BAR_RGBA[3]}>]"
sed "s|{{BAR_RGBA}}|$BAR_RGBA_GV|g" "$HERE/config/panel/config.txt.in" > "$PDIR/config.txt"
if [[ $DOCK == plank ]]; then
  # Plank is the dock: drop Docklike's panel (panel-2 / plugin-10) from the layout.
  sed -i -e '/^\/panels\/panel-2\//d' -e '/^\/plugins\/plugin-10/d' "$PDIR/config.txt"
fi
if [[ $DO_GLOBAL_MENU -eq 0 ]]; then
  sed -i -e "s|^/plugins/plugin-2 'appmenu'|/plugins/plugin-2 'separator'|" -e '/^\/plugins\/plugin-2\//d' "$PDIR/config.txt"
fi
mkdir -p "$PDIR/launcher-11" "$PDIR/launcher-12"
printf '[Desktop Entry]\nType=Application\nName=Spotlight\nComment=Search apps (Super+Space)\nExec=rofi -show drun -theme %s\nIcon=system-search-symbolic\nStartupNotify=false\n' \
  "$CONF_DIR/rofi/spotlight.rasi" > "$PDIR/launcher-12/cupertino-spotlight.desktop"
sed "s|^Exec=.*|Exec=$BIN_DIR/cupertino-control-center|" "$HERE/config/icons/cupertino-control-center.desktop" \
  > "$PDIR/launcher-11/cupertino-control-center.desktop"

APPMENU_IDS=(); [[ $DO_GLOBAL_MENU -eq 1 ]] && APPMENU_IDS=(2)
CLOCK_IDS=(8); BAR_PANELS=(1); PANEL_IDS=(1 2)
[[ $DOCK == plank ]] && PANEL_IDS=(1)
panels_line="/panels ["; first=1
for p in "${PANEL_IDS[@]}"; do panels_line+=$([[ $first -eq 1 ]] && echo "<$p>" || echo ", <$p>"); first=0; done
sed -i "s|^/panels \[.*\]$|$panels_line]|" "$PDIR/config.txt"

# Dock apps: Files, Launchpad, browser, terminal, text editor, settings (whatever exists).
PINS=()
add_pin() { local f; if f=$(find_desktop "$@"); then PINS+=("$f"); fi; }
add_pin thunar.desktop org.xfce.thunar.desktop pcmanfm.desktop nemo.desktop org.gnome.Nautilus.desktop
PINS+=("$LAUNCHPAD_DESKTOP")
add_pin firefox-esr.desktop firefox.desktop chromium.desktop google-chrome.desktop brave-browser.desktop
add_pin qterminal.desktop xfce4-terminal.desktop org.xfce.terminal.desktop kitty.desktop
add_pin org.xfce.mousepad.desktop mousepad.desktop
add_pin xfce-settings-manager.desktop org.xfce.settings.manager.desktop
{
  echo "[user]"
  printf 'pinned='; printf '%s;' "${PINS[@]}"; echo
  echo "indicatorStyle=1"
  echo "inactiveIndicatorStyle=1"
  echo "indicatorOrientation=0"
  echo "indicatorColorFromTheme=false"
  echo "customIndicatorColors=true"
  echo "indicatorColor=$DOT_COLOR"
  echo "inactiveColor=$DOT_COLOR"
  echo "noWindowsListIfSingle=true"
} > "$PDIR/docklike-10.rc"

if [[ $DOCK == plank ]]; then
  (cd "$PDIR" && tar -cjf "$CONF_DIR/panel-layout.tar.bz2" config.txt launcher-11 launcher-12)
else
  (cd "$PDIR" && tar -cjf "$CONF_DIR/panel-layout.tar.bz2" config.txt docklike-10.rc launcher-11 launcher-12)
fi
rm -rf "$PDIR"
state_set APPMENU_IDS "${APPMENU_IDS[*]}"
state_set CLOCK_IDS "${CLOCK_IDS[*]}"
state_set BAR_PANELS "${BAR_PANELS[*]}"
state_set DOCK "$DOCK"

state_set STATUS_WIDGETS "systray-4 pulseaudio-5 power-manager-plugin-7 launcher-11 launcher-12"
xfce4-panel-profiles load "$CONF_DIR/panel-layout.tar.bz2" >/dev/null 2>&1 || die "Loading the panel layout failed. Restore with ./uninstall.sh"
sleep 2
pgrep -u "$(id -u)" -x xfce4-panel >/dev/null || { setsid xfce4-panel >/dev/null 2>&1 < /dev/null & }
# The same full menu bar on every other monitor
if [[ $(sync_bars) == restart ]]; then xfce4-panel -r >/dev/null 2>&1 || true; sleep 2; fi
read -r -a BAR_PANELS <<<"$(state_get BAR_PANELS)"
ok "Menu bar on ${#BAR_PANELS[@]} monitor(s) and Control Center"

# ---- 8b. Plank: the magnifying dock ---------------------------------------------------
if [[ $DOCK == plank ]]; then
  log "Setting up the dock (Plank Reloaded)"
  mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/plank/themes"
  cp -r "$HERE"/config/plank/Cupertino-* "${XDG_DATA_HOME:-$HOME/.local/share}/plank/themes/"
  LDIR="${XDG_CONFIG_HOME:-$HOME/.config}/plank/dock1/launchers"; mkdir -p "$LDIR"
  ITEMS=()
  for f in "${PINS[@]}"; do
    n="$(basename "$f" .desktop).dockitem"
    printf '[PlankDockItemPreferences]\nLauncher=file://%s\n' "$f" > "$LDIR/$n"
    ITEMS+=("'$n'")
  done
  # Right end, like macOS: a separator, the Downloads folder and the Trash.
  DL=$(xdg-user-dir DOWNLOAD 2>/dev/null || echo "$HOME/Downloads"); mkdir -p "$DL"
  printf '[PlankDockItemPreferences]\nLauncher=docklet://separator\n' > "$LDIR/zz-separator.dockitem"
  printf '[PlankDockItemPreferences]\nLauncher=file://%s\n' "$DL" > "$LDIR/zz-downloads.dockitem"
  printf '[PlankDockItemPreferences]\nLauncher=docklet://trash\n' > "$LDIR/zz-trash.dockitem"
  ITEMS+=("'zz-separator.dockitem'" "'zz-downloads.dockitem'" "'zz-trash.dockitem'")
  PS="net.launchpad.plank.dock.settings:/net/launchpad/plank/docks/dock1/"
  pkill -u "$(id -u)" -x plank 2>/dev/null || true
  gsettings set "$PS" dock-items "[$(IFS=,; echo "${ITEMS[*]}")]"
  gsettings set "$PS" theme "$PLANK_THEME"
  gsettings set "$PS" zoom-enabled true
  gsettings set "$PS" zoom-percent 165
  gsettings set "$PS" icon-size 48
  gsettings set "$PS" hide-mode "'intelligent'"
  gsettings set "$PS" position "'bottom'"
  gsettings set "$PS" alignment "'center'"
  gsettings set "$PS" gap-size 6
  # a dock on every monitor, always there (sync_docks copies these settings to each)
  gsettings set "$PS" active-display false 2>/dev/null || true
  gsettings set "$PS" show-dock-item false
  gsettings set "$PS" tooltips-enabled true
  gsettings set "$PS" lock-items false
  gsettings set "$PS" anchor-docklets true 2>/dev/null || true
  mkdir -p "$(dirname "$AUTOSTART_PLANK")"
  printf '[Desktop Entry]\nType=Application\nName=Dock (cupertino-xfce)\nExec="%s" docks\nOnlyShowIn=XFCE;\nX-GNOME-Autostart-enabled=true\n' "$BIN_DIR/cupertino-xfce-mode" > "$AUTOSTART_PLANK"
  "$BIN_DIR/cupertino-xfce-mode" docks
  sleep 2
  if pgrep -u "$(id -u)" -x plank >/dev/null; then ok "Dock running: magnifies on hover, floats above the screen edge"
  else warn "Plank didn't start; run 'plank' in a terminal to see why."; fi
fi

# ---- 9. terminal ---------------------------------------------------------------------
if [[ $DO_TERMINAL -eq 1 ]]; then
  log "Setting QTerminal's colours and font"
  apply_ini "$QT_INI" General colorScheme "$TERM_SCHEME"
  apply_ini "$QT_INI" General fontFamily "JetBrains Mono"
  apply_ini "$QT_INI" General fontSize 11
  apply_ini "$QT_INI" General TerminalTransparency 0
  apply_ini "$QT_INI" General ApplicationTransparency 0
  printf 'General\tfontFamily\tJetBrains Mono\nGeneral\tfontSize\t11\nGeneral\tTerminalTransparency\t0\nGeneral\tApplicationTransparency\t0\n' > "$CONF_DIR/qterminal.keys"
  # A QTerminal that's open now saves its old settings when it closes, so apply once more
  # at next login.
  mkdir -p "$(dirname "$ONCE_AUTOSTART")"
  cat > "$ONCE_AUTOSTART" <<EOF
[Desktop Entry]
Type=Application
Name=cupertino-xfce (finish setup)
Exec="$BIN_DIR/cupertino-xfce-mode" once
OnlyShowIn=XFCE;
X-GNOME-Autostart-enabled=true
EOF
  ok "Cupertino terminal colours, JetBrains Mono 11 (fully applies to new windows after next login)"
fi

# ---- 10. Firefox ---------------------------------------------------------------------
if [[ $DO_FIREFOX -eq 1 ]]; then
  log "Giving Firefox the WhiteSur (Safari-style) look"
  fetch_repo WhiteSur-firefox-theme "$WHITESUR_FIREFOX_URL" "$WHITESUR_FIREFOX_COMMIT"
  FS="$SRC_DIR/WhiteSur-firefox-theme/src"; FC="$DATA_DIR/firefox/chrome"
  rm -rf "$FC"; mkdir -p "$FC"
  cp -r "$FS/WhiteSur" "$FC/"
  cp -f "$FS/customChrome.css" "$FC/"
  cp -r "$FS/common/icons" "$FS/common/titlebuttons" "$FS/common/pages" "$FC/WhiteSur/" 2>/dev/null || true
  cp -f "$FS"/common/*.css "$FC/WhiteSur/" 2>/dev/null || true
  mkdir -p "$FC/WhiteSur/parts"; cp -f "$FS"/common/parts/*.css "$FC/WhiteSur/parts/" 2>/dev/null || true
  cp -f "$FS/userChrome-WhiteSur.css" "$FC/userChrome.css"
  cp -f "$FS/userContent-WhiteSur.css" "$FC/userContent.css"
  for prof in "${FF_PROFILES[@]}"; do
    name=$(basename "$prof"); pb="$BACKUP_DIR/firefox/$name"; mkdir -p "$pb"
    if [[ -L $prof/chrome && $(readlink "$prof/chrome") == "$FC" ]]; then :
    elif [[ -e $prof/chrome ]]; then mv "$prof/chrome" "$pb/chrome"
    fi
    ln -sfn "$FC" "$prof/chrome"
    if [[ -f $prof/user.js ]]; then cp -a "$prof/user.js" "$pb/user.js"; else touch "$pb/no-user.js"; fi
    sed -i '/>>> cupertino-xfce/,/<<< cupertino-xfce/d' "$prof/user.js" 2>/dev/null || true
    cat >> "$prof/user.js" <<'EOF'
// >>> cupertino-xfce (WhiteSur Firefox theme) >>>
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
user_pref("browser.tabs.drawInTitlebar", true);
user_pref("browser.uidensity", 0);
user_pref("mozilla.widget.use-argb-visuals", true);
user_pref("widget.gtk.rounded-bottom-corners.enabled", true);
user_pref("svg.context-properties.content.enabled", true);
// <<< cupertino-xfce <<<
EOF
    printf '%s\n' "$prof" >> "$BACKUP_DIR/firefox/profiles.txt"
  done
  ok "Firefox themed (${#FF_PROFILES[@]} profile(s)); restart Firefox to see it"
fi

# ---- 11. light/dark look -------------------------------------------------------------
log "Applying $MODE mode"
NO_PANEL_RESTART=1 WALLPAPER_ALL=1 apply_mode "$MODE"
xfce4-panel -r >/dev/null 2>&1 || true
ok "$MODE mode (switch any time: Control Center, or cupertino-xfce-mode toggle)"

# ---- 12. picom: blur, rounded corners, shadows ----------------------------------------
if [[ $DO_EFFECTS -eq 1 ]]; then
  log "Starting picom for blur, rounded corners and shadows"
  install -Dm644 "$HERE/config/picom.conf" "$CONF_DIR/picom.conf"
  mkdir -p "$(dirname "$AUTOSTART_PICOM")"
  cat > "$AUTOSTART_PICOM" <<EOF
[Desktop Entry]
Type=Application
Name=picom (cupertino-xfce)
Comment=Blur, rounded corners and shadows
Exec=picom --config "$CONF_DIR/picom.conf"
OnlyShowIn=XFCE;
X-GNOME-Autostart-enabled=true
EOF
  # The picom package starts its own picom at login (/etc/xdg/autostart/picom.desktop,
  # with ~/.config/picom). Only one compositor can run: whichever starts first wins, so
  # turn the stock one off for you, or the dock ends up blurred some logins and not others.
  STOCK_PICOM="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/picom.desktop"
  if [[ -f /etc/xdg/autostart/picom.desktop && ! -e $STOCK_PICOM ]]; then
    printf '[Desktop Entry]\nType=Application\nName=picom\nHidden=true\nX-Cupertino-Xfce=true\n' > "$STOCK_PICOM"
  fi
  if pgrep -u "$(id -u)" -x picom >/dev/null; then pkill -u "$(id -u)" -x picom || true; sleep 1; fi
  apply_prop xfwm4 /general/use_compositing bool false
  setsid picom --config "$CONF_DIR/picom.conf" >/dev/null 2>&1 < /dev/null &
  sleep 3
  if pgrep -u "$(id -u)" -x picom >/dev/null; then
    ok "picom running"
  else
    warn "picom couldn't start (often a GPU/GLX issue). Falling back to Xfce's compositor: no blur or rounded corners."
    rm -f "$AUTOSTART_PICOM"
    xset_prop xfwm4 /general/use_compositing bool true
  fi
fi

# ---- 12b. background helper: standard menus for apps without any, and a wallpaper and
#          menu bar on every monitor when monitors are plugged in or out
mkdir -p "$(dirname "$AUTOSTART_MENUD")"
cat > "$AUTOSTART_MENUD" <<EOF
[Desktop Entry]
Type=Application
Name=cupertino-xfce helper
Comment=Standard menus for apps without any; menu bar and wallpaper on every monitor
Exec="$BIN_DIR/cupertino-menud"
OnlyShowIn=XFCE;
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF
pkill -u "$(id -u)" -f 'python3 .*cupertino-menu[d]' 2>/dev/null || true
setsid "$BIN_DIR/cupertino-menud" >/dev/null 2>&1 < /dev/null &
ok "Helper running: menus for apps without any, a menu bar on every monitor"

# ---- 13. system styling (root): login screen, terminal schemes, boot splash ------------
ROOT2="$BACKUP_DIR/root-system.sh"
echo "set -e" > "$ROOT2"
if [[ $USE_LIGHTDM_GTK -eq 1 ]]; then
  cp -a "$GREETER_CONF" "$BACKUP_DIR/lightdm-gtk-greeter.conf"
  cat >> "$ROOT2" <<EOF
rm -rf /usr/share/themes/WhiteSur-Login /usr/share/icons/WhiteSur /usr/share/icons/WhiteSur-cursors
cp -a "$HOME/.themes/WhiteSur-Dark" /usr/share/themes/WhiteSur-Login
sed -i 's/^Name=.*/Name=WhiteSur-Login/' /usr/share/themes/WhiteSur-Login/index.theme
cat "$HERE/config/greeter/greeter.css" >> /usr/share/themes/WhiteSur-Login/gtk-3.0/gtk.css
cp -a "$ICON_DST/WhiteSur" /usr/share/icons/WhiteSur
cp -a "$HOME/.icons/WhiteSur-cursors" /usr/share/icons/WhiteSur-cursors
install -Dm644 "$HERE/wallpapers/$WALLPAPER-blurred.jpg" /usr/share/backgrounds/cupertino-xfce/login.jpg
chown -R root:root /usr/share/themes/WhiteSur-Login /usr/share/icons/WhiteSur /usr/share/icons/WhiteSur-cursors /usr/share/backgrounds/cupertino-xfce
chmod -R a+rX /usr/share/themes/WhiteSur-Login /usr/share/icons/WhiteSur /usr/share/icons/WhiteSur-cursors /usr/share/backgrounds/cupertino-xfce
python3 "$HERE/lib/set-greeter.py" "$GREETER_CONF"
echo applied > "$BACKUP_DIR/login.applied"
EOF
fi
if [[ $DO_TERMINAL -eq 1 ]]; then
  echo "install -m644 \"$HERE/config/terminal/Cupertino-Light.colorscheme\" \"$HERE/config/terminal/Cupertino-Dark.colorscheme\" \"$QTW_DIR/\"" >> "$ROOT2"
  echo "$QTW_DIR" > "$BACKUP_DIR/qtermwidget-dir"
fi
if [[ $DO_BOOT -eq 1 ]]; then
  plymouth-set-default-theme 2>/dev/null > "$BACKUP_DIR/plymouth.theme" || echo "" > "$BACKUP_DIR/plymouth.theme"
  cat >> "$ROOT2" <<EOF
rm -rf /usr/share/plymouth/themes/cupertino
cp -r "$HERE/config/plymouth/cupertino" /usr/share/plymouth/themes/cupertino
chown -R root:root /usr/share/plymouth/themes/cupertino
plymouth-set-default-theme -R cupertino
echo applied > "$BACKUP_DIR/boot.applied"
EOF
fi
chown "$(id -u):$(id -g)" "$ROOT2"
if [[ $(wc -l < "$ROOT2") -gt 1 ]]; then
  log "Styling the login screen, terminal and boot splash (password again; the boot splash takes a minute)"
  if as_root_script "$ROOT2"; then ok "System styling applied"
  else warn "System styling step failed; your login screen and boot splash may be unchanged."; fi
fi

cat <<EOF

${C_GRN}Done.${C_OFF} Your Mac-style desktop is ready.
  • Spotlight: Super+Space        • Mission Control: Ctrl+Up
  • Control Center: the toggles icon next to the clock (light/dark, Wi-Fi, sound…)
  • Launchpad: the grid icon in the dock   • Screenshots: Super+Shift+3 / 4 / 5
  • Log out and back in so every app sends its menus to the menu bar.
  • Undo everything:  $HERE/uninstall.sh
EOF
