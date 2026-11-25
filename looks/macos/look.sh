# shellcheck shell=bash
# shellcheck disable=SC2034  # LOOK_* are read by the looks command
# macOS look for KDE Plasma 6: WhiteSur theme, a menu bar with global menu on every
# screen, a magnifying dock (Plank Reloaded on X11; a floating panel on Wayland),
# Spotlight (KRunner), Launchpad and Mission Control (KWin Overview).

LOOK_TITLE="macOS"
LOOK_VARIANTS=(light dark)
LOOK_SESSION=""   # applies inside a normal Plasma session

# Pinned upstreams (the versions this look was tested with)
WHITESUR_KDE_URL="https://github.com/vinceliuice/WhiteSur-kde.git"
WHITESUR_KDE_COMMIT="cf4df59ce91004f7ea39358b1b8ff917d5c329f7"
WHITESUR_GTK_URL="https://github.com/vinceliuice/WhiteSur-gtk-theme.git"
WHITESUR_GTK_COMMIT="d5782652d412137e26fb8ff55b55a5572e4c6995"
WHITESUR_ICON_URL="https://github.com/vinceliuice/WhiteSur-icon-theme.git"
WHITESUR_ICON_COMMIT="73d8040da51a9ed74e47c7366e7e9ff437601a5c"
WHITESUR_CURSOR_URL="https://github.com/vinceliuice/WhiteSur-cursors.git"
WHITESUR_CURSOR_COMMIT="e190baf618ed95ee217d2fd45589bd309b37672b"
SHA_WHITESUR_LIGHT="2635570e218afab2d34b0663287054f7b995b9f7f810e97410dcad389987d5ba"
SHA_WHITESUR_DARK="98ac7545ec5290b718875fdfbdd7f0f6b88126103d1eec259ec9fbf80be7b75f"

# Plank Reloaded (the magnifying dock): from the distro if packaged, otherwise its
# author's Debian build, checksum-pinned. Format: "<arch> <file> <sha256>"
PLANK_REPO="https://zquestz.github.io/ppa/debian"
PLANK_DEBS=(
  "amd64 plank-reloaded-debian_0.11.178-1_amd64.deb aaa055faffda483b64f24e1f130fc039f99f18da87c6c3c30210c748e0c8d3e6"
  "arm64 plank-reloaded-debian_0.11.178-1_arm64.deb bea8743bffbf924740240e4e59d578028b099cceba6b491f0689ccd24f689465"
)

MAC_PLANK_DOCK="looks-macos"
MAC_PLANK_AUTOSTART="$CONF_HOME/autostart/kali-looks-plank.desktop"
MAC_LAUNCHPAD_DESKTOP="$LOCAL_SHARE/applications/kali-looks-launchpad.desktop"

mac_lnf_id() { [[ $1 == dark ]] && echo "io.github.iiciel.looks.macos-dark" || echo "io.github.iiciel.looks.macos"; }

install_plank() {
  pkg_installed plank-reloaded && return 0
  if pkg_installed plank; then
    warn "The original 'plank' package is installed and conflicts with Plank Reloaded; using a dock panel instead."
    return 1
  fi
  if apt_has plank-reloaded; then need_packages plank-reloaded; return 0; fi
  local arch entry a f h dir="$SRC_DIR/plank"
  arch=$(dpkg --print-architecture)
  for entry in "${PLANK_DEBS[@]}"; do
    read -r a f h <<<"$entry"
    [[ $a == "$arch" ]] || continue
    mkdir -p "$dir"
    [[ -f $dir/$f ]] && sha_ok "$dir/$f" "$h" || curl -fsSL -o "$dir/$f" "$PLANK_REPO/$f" || die "Couldn't download Plank Reloaded."
    sha_ok "$dir/$f" "$h" || die "Plank Reloaded checksum mismatch."
    log "Installing Plank Reloaded (the magnifying dock; asks for your password)"
    as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "$dir/$f" || die "Installing Plank Reloaded failed."
    return 0
  done
  warn "No Plank Reloaded build for $arch; using a dock panel instead."
  return 1
}

look_prepare() {
  need_packages git curl xz-utils qt-style-kvantum rofi fonts-inter appmenu-gtk3-module xdg-user-dirs
  log "Fetching WhiteSur for Plasma, GTK apps, icons and cursors"
  fetch_repo WhiteSur-kde "$WHITESUR_KDE_URL" "$WHITESUR_KDE_COMMIT"
  fetch_repo WhiteSur-gtk-theme "$WHITESUR_GTK_URL" "$WHITESUR_GTK_COMMIT"
  fetch_repo WhiteSur-icon-theme "$WHITESUR_ICON_URL" "$WHITESUR_ICON_COMMIT"
  fetch_repo WhiteSur-cursors "$WHITESUR_CURSOR_URL" "$WHITESUR_CURSOR_COMMIT"

  # Plasma side: copy the parts we use (no upstream install script is run)
  local K="$SRC_DIR/WhiteSur-kde" v
  mkdir -p "$CONF_HOME/Kvantum" "$LOCAL_SHARE"/{color-schemes,aurorae/themes,plasma/desktoptheme,wallpapers}
  rm -rf "$CONF_HOME/Kvantum/WhiteSur"; cp -r "$K/Kvantum/WhiteSur" "$CONF_HOME/Kvantum/"
  cp "$K"/color-schemes/WhiteSur{,Dark}.colors "$LOCAL_SHARE/color-schemes/"
  for v in WhiteSur WhiteSur-dark; do
    rm -rf "$LOCAL_SHARE/plasma/desktoptheme/$v"
    cp -r "$K/plasma/desktoptheme/$v" "$LOCAL_SHARE/plasma/desktoptheme/"
    cp -r "$K"/plasma/desktoptheme/{icons,weather} "$LOCAL_SHARE/plasma/desktoptheme/$v/"
  done
  local color A
  for color in "" "-dark"; do
    A="$LOCAL_SHARE/aurorae/themes/WhiteSur$color"
    rm -rf "$A"
    cp -r "$K/aurorae/main/WhiteSur$color" "$A"
    cp "$K/aurorae/common/assets$color/"*.svg "$A/"
    cp "$K"/aurorae/{metadata.desktop,metadata.json} "$A/"
    cp "$K/aurorae/main/WhiteSur${color}rc" "$A/WhiteSur${color}rc"
    sed -i "s/WhiteSur/WhiteSur$color/g" "$A/metadata.desktop" "$A/metadata.json"
  done

  # GTK apps (Firefox, etc.), icons, cursors: same as cupertino-xfce
  local REL="$SRC_DIR/WhiteSur-gtk-theme/release"
  sha_ok "$REL/WhiteSur-Light.tar.xz" "$SHA_WHITESUR_LIGHT" || die "WhiteSur-Light archive checksum mismatch."
  sha_ok "$REL/WhiteSur-Dark.tar.xz" "$SHA_WHITESUR_DARK" || die "WhiteSur-Dark archive checksum mismatch."
  mkdir -p "$HOME/.themes" "$HOME/.icons" "$LOCAL_SHARE/icons"
  [[ -d $HOME/.themes/WhiteSur-Light ]] || tar -xJf "$REL/WhiteSur-Light.tar.xz" -C "$HOME/.themes"
  [[ -d $HOME/.themes/WhiteSur-Dark ]] || tar -xJf "$REL/WhiteSur-Dark.tar.xz" -C "$HOME/.themes"
  local ICON_SRC="$SRC_DIR/WhiteSur-icon-theme" T="$LOCAL_SHARE/icons/WhiteSur"
  if [[ ! -f $T/index.theme ]]; then
    mkdir -p "$T/status"
    cp "$ICON_SRC/src/index.theme" "$T/"
    cp -r "$ICON_SRC"/src/{actions,animations,apps,categories,devices,emotes,emblems,mimes,places,preferences} "$T/"
    cp -r "$ICON_SRC"/src/status/{16,22,24,32,symbolic} "$T/status/"
    rm -f "$T"/places/scalable/user-trash{,-full}-dark.svg
    cp -r "$ICON_SRC"/links/{actions,apps,categories,devices,emotes,emblems,mimes,places,status,preferences} "$T/"
    gtk-update-icon-cache -q "$T" 2>/dev/null || true
  fi
  [[ -d $HOME/.icons/WhiteSur-cursors ]] || cp -r "$SRC_DIR/WhiteSur-cursors/dist" "$HOME/.icons/WhiteSur-cursors"

  # Wallpapers and our two Plasma global themes (light/dark)
  mkdir -p "$LOCAL_SHARE/backgrounds/kali-looks"
  cp "$HERE"/wallpapers/macos/*.jpg "$LOCAL_SHARE/backgrounds/kali-looks/"
  local variant id dir dock="panel"
  if ! is_wayland && install_plank; then dock="plank"; fi
  state_set MACOS_DOCK "$dock"
  for variant in light dark; do
    id=$(mac_lnf_id "$variant"); dir="$LOCAL_SHARE/plasma/look-and-feel/$id"
    rm -rf "$dir"; mkdir -p "$dir/contents/layouts"
    mac_metadata "$id" "$variant" > "$dir/metadata.json"
    mac_defaults "$variant" > "$dir/contents/defaults"
    { echo "var LOOKS_DOCK = \"$dock\";"; cat "$LOOK_DIR/layout.js"; } > "$dir/contents/layouts/org.kde.plasma.desktop-layout.js"
  done

  # Plank themes and Launchpad
  mkdir -p "$LOCAL_SHARE/plank/themes" "$(dirname "$MAC_LAUNCHPAD_DESKTOP")"
  cp -r "$LOOK_DIR"/plank/Cupertino-* "$LOCAL_SHARE/plank/themes/"
  ok "macOS look ready"
}

mac_metadata() {
  local id=$1 variant=$2 name="macOS (kali-looks)"
  [[ $variant == dark ]] && name="macOS Dark (kali-looks)"
  cat <<EOF
{
  "KPackageStructure": "Plasma/LookAndFeel",
  "KPlugin": {
    "Authors": [{ "Name": "kali-looks" }],
    "Category": "Global Themes (Plasma 6)",
    "Description": "macOS-style menu bar on every screen, dock and WhiteSur theme",
    "Id": "$id",
    "License": "GPLv3",
    "Name": "$name",
    "Website": "https://github.com/iiCiel/kali-looks"
  },
  "X-KDE-fallbackPackage": "org.kde.breeze.desktop",
  "X-Plasma-APIVersion": "2"
}
EOF
}

mac_defaults() {
  if [[ $1 == dark ]]; then
    local scheme=WhiteSurDark plasma=WhiteSur-dark deco=WhiteSur-dark style=kvantum-dark
  else
    local scheme=WhiteSur plasma=WhiteSur deco=WhiteSur style=kvantum
  fi
  cat <<EOF
[kcminputrc][Mouse]
cursorTheme=WhiteSur-cursors

[kdeglobals][General]
ColorScheme=$scheme

[kdeglobals][Icons]
Theme=WhiteSur

[kdeglobals][KDE]
widgetStyle=$style

[kwinrc][org.kde.kdecoration2]
ButtonsOnLeft=XIA
ButtonsOnRight=
library=org.kde.kwin.aurorae
theme=__aurorae__svg__$deco

[plasmarc][Theme]
name=$plasma
EOF
}

mac_dock_items() {
  local LDIR="$CONF_HOME/plank/$MAC_PLANK_DOCK/launchers" f n; local -a items=()
  rm -rf "$LDIR"; mkdir -p "$LDIR"
  for f in "/usr/share/applications/org.kde.dolphin.desktop" "$MAC_LAUNCHPAD_DESKTOP" \
           /usr/share/applications/{firefox-esr,firefox,chromium}.desktop \
           /usr/share/applications/org.kde.konsole.desktop /usr/share/applications/org.kde.kate.desktop \
           /usr/share/applications/systemsettings.desktop; do
    [[ -f $f ]] || continue
    [[ $f == */firefox.desktop && -f /usr/share/applications/firefox-esr.desktop ]] && continue
    [[ $f == */chromium.desktop && ( -f /usr/share/applications/firefox-esr.desktop || -f /usr/share/applications/firefox.desktop ) ]] && continue
    n="$(basename "$f" .desktop).dockitem"
    printf '[PlankDockItemPreferences]\nLauncher=file://%s\n' "$f" > "$LDIR/$n"
    items+=("'$n'")
  done
  local DL; DL=$(xdg-user-dir DOWNLOAD 2>/dev/null || echo "$HOME/Downloads"); mkdir -p "$DL"
  printf '[PlankDockItemPreferences]\nLauncher=docklet://separator\n' > "$LDIR/zz-separator.dockitem"
  printf '[PlankDockItemPreferences]\nLauncher=file://%s\n' "$DL" > "$LDIR/zz-downloads.dockitem"
  printf '[PlankDockItemPreferences]\nLauncher=docklet://trash\n' > "$LDIR/zz-trash.dockitem"
  items+=("'zz-separator.dockitem'" "'zz-downloads.dockitem'" "'zz-trash.dockitem'")
  (IFS=,; echo "[${items[*]}]")
}

mac_start_plank() {
  local variant=$1 theme=Cupertino-Light PS="net.launchpad.plank.dock.settings:/net/launchpad/plank/docks/$MAC_PLANK_DOCK/"
  [[ $variant == dark ]] && theme=Cupertino-Dark
  pkill -u "$(id -u)" -f "plank -n $MAC_PLANK_DOCK" 2>/dev/null || true
  gsettings set "$PS" dock-items "$(mac_dock_items)"
  gsettings set "$PS" theme "$theme"
  gsettings set "$PS" zoom-enabled true
  gsettings set "$PS" zoom-percent 165
  gsettings set "$PS" icon-size 48
  gsettings set "$PS" hide-mode "'intelligent'"
  gsettings set "$PS" position "'bottom'"
  gsettings set "$PS" alignment "'center'"
  gsettings set "$PS" gap-size 6
  gsettings set "$PS" active-display true 2>/dev/null || true
  gsettings set "$PS" show-dock-item false
  gsettings set "$PS" anchor-docklets true 2>/dev/null || true
  mkdir -p "$(dirname "$MAC_PLANK_AUTOSTART")"
  printf '[Desktop Entry]\nType=Application\nName=Dock (kali-looks macOS)\nExec=plank -n %s\nOnlyShowIn=KDE;\nX-GNOME-Autostart-enabled=true\n' \
    "$MAC_PLANK_DOCK" > "$MAC_PLANK_AUTOSTART"
  setsid plank -n "$MAC_PLANK_DOCK" >/dev/null 2>&1 < /dev/null &
}

look_apply() {
  local variant=${1:-light} icon_theme=WhiteSur wp gtk
  [[ $variant == dark ]] && wp=dusk-waves || wp=blue-waves
  [[ $variant == dark ]] && gtk=WhiteSur-Dark || gtk=WhiteSur-Light

  # Launchpad: full-screen app grid (rofi), in the dock and on F4 like a Mac keyboard
  sed -e "s|{{ICON_THEME}}|$icon_theme|g" "$LOOK_DIR/launchpad.rasi.in" > "$CONF_DIR/launchpad.rasi"
  printf '[Desktop Entry]\nType=Application\nName=Launchpad\nComment=Show all apps\nExec=rofi -show drun -theme %s\nIcon=view-app-grid\nCategories=Utility;\n' \
    "$CONF_DIR/launchpad.rasi" > "$MAC_LAUNCHPAD_DESKTOP"

  log "Applying the macOS look ($variant)"
  plasma-apply-lookandfeel -a "$(mac_lnf_id "$variant")" --resetLayout >/dev/null 2>&1 \
    || die "Plasma refused the macOS global theme."
  kwriteconfig6 --file "$CONF_HOME/Kvantum/kvantum.kvconfig" --group General --key theme \
    "$([[ $variant == dark ]] && echo WhiteSurDark || echo WhiteSur)"
  plasma-apply-wallpaperimage "$LOCAL_SHARE/backgrounds/kali-looks/$wp.jpg" >/dev/null 2>&1 || true
  # Window buttons on the left in Mac order (Plasma's theme loader skips these keys)
  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft "XIA"
  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight ""

  # GTK apps follow the look; Inter like macOS's San Francisco
  kwriteconfig6 --file "$CONF_HOME/gtk-3.0/settings.ini" --group Settings --key gtk-theme-name "$gtk"
  kwriteconfig6 --file "$CONF_HOME/gtk-4.0/settings.ini" --group Settings --key gtk-theme-name "$gtk"
  qdbus org.kde.GtkConfig /GtkConfig org.kde.GtkConfig.setGtkTheme "$gtk" >/dev/null 2>&1 || true
  kwriteconfig6 --file kdeglobals --group General --key font "Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
  kwriteconfig6 --file kdeglobals --group General --key menuFont "Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
  kwriteconfig6 --file kdeglobals --group General --key toolBarFont "Inter,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
  kwriteconfig6 --file kdeglobals --group WM --key activeFont "Inter,10,-1,5,600,0,0,0,0,0,0,0,0,0,0,1"

  # Mac shortcuts: Spotlight (Meta+Space), Mission Control (Ctrl+Up), Launchpad (F4)
  kwriteconfig6 --file kglobalshortcutsrc --group services --group org.kde.krunner.desktop \
    --key _launch "Meta+Space	Alt+Space	Search"
  kwriteconfig6 --file kglobalshortcutsrc --group kwin --key Overview "Ctrl+Up	Meta+W,Meta+W,Toggle Overview"
  kwriteconfig6 --file kglobalshortcutsrc --group services --group kali-looks-launchpad.desktop --key _launch "F4"
  kwriteconfig6 --file krunnerrc --group General --key FreeFloating true

  # The dock
  if [[ $(state_get MACOS_DOCK) == plank ]] && ! is_wayland; then
    mac_start_plank "$variant"
  fi
  reconfigure_kwin
  ok "macOS look applied. Some shortcuts take effect after logging out and back in."
}

look_leave() {
  pkill -u "$(id -u)" -f "plank -n $MAC_PLANK_DOCK" 2>/dev/null || true
  rm -f "$MAC_PLANK_AUTOSTART"
}
