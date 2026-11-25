# shellcheck shell=bash
# shellcheck disable=SC2034  # LOOK_* are read by the looks command
# Windows XP look for KDE Plasma 6: "Expose" Luna theme (Plasma theme, window borders,
# Qt style, colours, wallpaper) by phob1an, B00merang's Windows XP Luna for GTK apps,
# and a blue taskbar with a green start button on every screen.

LOOK_TITLE="Windows XP"
LOOK_VARIANTS=(luna)
LOOK_SESSION=""

# Pinned upstreams
EXPOSE_URL="https://www.opencode.net/phob1an/expose.git"
EXPOSE_COMMIT="09d4ddb30a345cb35f638219bd792296dfbf01f2"
XP_GTK_URL="https://github.com/B00merang-Project/Windows-XP.git"
XP_GTK_COMMIT="7637830906823af40a3cd7e7079be753d8b7d679"

XP_LNF_ID="io.github.iiciel.looks.winxp"
XP_GTK_THEME="Windows XP Luna"

look_prepare() {
  need_packages git qt-style-kvantum fonts-dejavu-core
  log "Fetching the Expose (XP Luna) theme and Windows XP for GTK apps"
  fetch_repo expose "$EXPOSE_URL" "$EXPOSE_COMMIT"
  fetch_repo Windows-XP "$XP_GTK_URL" "$XP_GTK_COMMIT"

  local E="$SRC_DIR/expose"
  mkdir -p "$CONF_HOME/Kvantum" "$LOCAL_SHARE"/{color-schemes,aurorae/themes,plasma/desktoptheme,wallpapers}
  rm -rf "$LOCAL_SHARE/plasma/desktoptheme/expose" "$LOCAL_SHARE/aurorae/themes/expose" "$CONF_HOME/Kvantum/Expose"
  cp -r "$E/desktoptheme/expose" "$LOCAL_SHARE/plasma/desktoptheme/"
  cp -r "$E/themes/expose" "$LOCAL_SHARE/aurorae/themes/"
  cp -r "$E/Kvantum/Expose" "$CONF_HOME/Kvantum/"
  cp "$E/Expose.colors" "$LOCAL_SHARE/color-schemes/"
  rm -rf "$LOCAL_SHARE/wallpapers/Bløff"; cp -r "$E/wallpapers/Bløff" "$LOCAL_SHARE/wallpapers/"

  # GTK apps (Firefox etc.)
  mkdir -p "$HOME/.themes"
  rm -rf "${HOME:?}/.themes/$XP_GTK_THEME"
  cp -r "$SRC_DIR/Windows-XP/$XP_GTK_THEME" "$HOME/.themes/"

  # The start button image and our Plasma global theme
  mkdir -p "$DATA_DIR"
  cp "$LOOK_DIR/start-button.png" "$DATA_DIR/xp-start-button.png"
  local dir="$LOCAL_SHARE/plasma/look-and-feel/$XP_LNF_ID"
  rm -rf "$dir"; mkdir -p "$dir/contents/layouts"
  cat > "$dir/metadata.json" <<EOF
{
  "KPackageStructure": "Plasma/LookAndFeel",
  "KPlugin": {
    "Authors": [{ "Name": "kali-looks" }],
    "Category": "Global Themes (Plasma 6)",
    "Description": "Windows XP-style taskbar on every screen with the Expose Luna theme",
    "Id": "$XP_LNF_ID",
    "License": "GPLv3",
    "Name": "Windows XP (kali-looks)",
    "Website": "https://github.com/iiCiel/kali-looks"
  },
  "X-KDE-fallbackPackage": "org.kde.breeze.desktop",
  "X-Plasma-APIVersion": "2"
}
EOF
  cat > "$dir/contents/defaults" <<'EOF'
[kdeglobals][General]
ColorScheme=Expose

[kdeglobals][KDE]
widgetStyle=kvantum

[kwinrc][org.kde.kdecoration2]
library=org.kde.kwin.aurorae
theme=__aurorae__svg__expose

[plasmarc][Theme]
name=expose
EOF
  { echo "var LOOKS_START_IMAGE = \"$DATA_DIR/xp-start-button.png\";"; cat "$LOOK_DIR/layout.js"; } \
    > "$dir/contents/layouts/org.kde.plasma.desktop-layout.js"
  ok "Windows XP look ready"
}

look_apply() {
  log "Applying the Windows XP look"
  plasma-apply-lookandfeel -a "$XP_LNF_ID" --resetLayout >/dev/null 2>&1 \
    || die "Plasma refused the Windows XP global theme."
  # Set each part explicitly too: the global-theme loader doesn't always reload them
  plasma-apply-desktoptheme expose >/dev/null 2>&1 || true
  plasma-apply-colorscheme Expose >/dev/null 2>&1 || true
  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.kde.kwin.aurorae
  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme __aurorae__svg__expose
  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft "M"
  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight "IAX"
  kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle kvantum
  kwriteconfig6 --file "$CONF_HOME/Kvantum/kvantum.kvconfig" --group General --key theme Expose
  # No XP icon set ships with it: use your own icons and cursor, not the previous look's
  local icons cursor
  icons=$(kreadconfig6 --file "$ORIG_DIR/config/kdeglobals" --group Icons --key Theme 2>/dev/null || true)
  cursor=$(kreadconfig6 --file "$ORIG_DIR/config/kcminputrc" --group Mouse --key cursorTheme 2>/dev/null || true)
  kwriteconfig6 --file kdeglobals --group Icons --key Theme "${icons:-breeze}"
  plasma-apply-cursortheme "${cursor:-breeze_cursors}" >/dev/null 2>&1 || true
  local wp; wp=$(find "$LOCAL_SHARE/wallpapers/Bløff" -name '*.png' -o -name '*.jpg' | sort | tail -n 1)
  [[ -n $wp ]] && plasma-apply-wallpaperimage "$wp" >/dev/null 2>&1 || true

  # GTK apps and fonts (Tahoma-like: DejaVu Sans at XP's small size)
  kwriteconfig6 --file "$CONF_HOME/gtk-3.0/settings.ini" --group Settings --key gtk-theme-name "$XP_GTK_THEME"
  kwriteconfig6 --file "$CONF_HOME/gtk-4.0/settings.ini" --group Settings --key gtk-theme-name "$XP_GTK_THEME"
  qdbus org.kde.GtkConfig /GtkConfig org.kde.GtkConfig.setGtkTheme "$XP_GTK_THEME" >/dev/null 2>&1 || true
  kwriteconfig6 --file kdeglobals --group General --key font "DejaVu Sans,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
  kwriteconfig6 --file kdeglobals --group General --key menuFont "DejaVu Sans,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
  kwriteconfig6 --file kdeglobals --group General --key toolBarFont "DejaVu Sans,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
  kwriteconfig6 --file kdeglobals --group WM --key activeFont "DejaVu Sans,10,-1,5,700,0,0,0,0,0,0,0,0,0,0,1"
  reconfigure_kwin
  ok "Windows XP look applied."
}
