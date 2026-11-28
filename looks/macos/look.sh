# shellcheck shell=bash
# shellcheck disable=SC2034  # LOOK_* are read by the looks command
# macOS Tahoe: "macOS Tahoe Shell for KDE" by Lester Cordero Murillo and contributors
# (https://github.com/lestercorderomurillo/macos-tahoe-liquid-kde, GPL-3.0): menu bar
# with global menus and Control Center, Liquid Glass dock, Launchpad, Finder look,
# SF Pro fonts, Tahoe icons/cursors/wallpapers, rounded window corners.
# Its own installer does the work; kali-looks points it at this look's config tree and
# leaves out the parts that would reach outside this session (Firefox, login and boot screens).

LOOK_TITLE="macOS Tahoe"
# Tahoe's own wallpaper package (light/dark picture follows the appearance)
LOOK_WALLPAPER="$HOME/.local/share/wallpapers/MacTahoe/"
MAC_REPO="https://github.com/lestercorderomurillo/macos-tahoe-liquid-kde.git"
MAC_COMMIT="aa482a96a689694564d0cec22987e35291274afb"   # 0.85.2
MAC_SRC="$SRC_DIR/macos-tahoe"

look_prepare() {
  # qmake6: the Tahoe installer asks it where Qt keeps its plugins and QML (a fresh Kali
  # doesn't have it, and the installer stops at its system check without it)
  need_packages python3-pyqt6 qmake6
  if [[ -d $MAC_SRC/.git ]] && [[ $(git -C "$MAC_SRC" rev-parse HEAD 2>/dev/null) == "$MAC_COMMIT" ]]; then return 0; fi
  log "Downloading macOS Tahoe Shell for KDE"
  rm -rf "$MAC_SRC"
  git clone -q --filter=blob:none "$MAC_REPO" "$MAC_SRC" || die "Couldn't download it."
  git -C "$MAC_SRC" checkout -q "$MAC_COMMIT" || die "Couldn't check out the tested version."
}

look_setup() {
  # Finder's full menu (Finder, File, Edit, View, Go, Window, Help) in the menu bar
  python3 "$LOOK_DIR/patch-finder-menu.py" "$MAC_SRC" || warn "Couldn't patch the Finder menu"
  # the bold "Finder" menu opens (About Finder, Settings, Empty Trash, Hide, Show All)
  python3 "$LOOK_DIR/patch-finder-app-menu.py" "$MAC_SRC" || warn "Couldn't patch Finder's own menu"
  # menu bar text white over the wallpaper (black over a very light one), as on a Mac
  python3 "$LOOK_DIR/patch-menubar-ink.py" "$MAC_SRC" || warn "Couldn't patch the menu bar colors"
  # Dock icons unchanged under the pointer, names only; menus' shortcuts in Mac symbols
  python3 "$LOOK_DIR/patch-dock-hover.py" "$MAC_SRC" || warn "Couldn't patch the Dock hover"
  # the Dock keeps floating above the edge next to maximized windows (its dots show)
  python3 "$LOOK_DIR/patch-dock-float.py" "$MAC_SRC" || warn "Couldn't patch the Dock's float"
  # Running apps keep a Dock icon, a dot and Quit, windows or not (looks dock-apps)
  python3 "$LOOK_DIR/patch-dock-running.py" "$MAC_SRC" || warn "Couldn't patch the Dock's running apps"
  python3 "$LOOK_DIR/patch-shortcut-symbols.py" "$MAC_SRC" || warn "Couldn't patch the menu shortcuts"
  log "Installing macOS Tahoe into its session (asks for your password; takes a few minutes)"
  # shellcheck disable=SC2016
  look_root env MTTKDE_NO_CONFIRM=1 MAC_TAHOE_NO_UPDATE_CHECK=true MTTKDE_NO_GRUB_MODIFY=1 \
    python3 "$MAC_SRC/src/scripts/installer_backend.py" install --light \
      --no-firefox --no-sddm --no-plymouth --no-nautilus --no-nautilus-bookmarks --no-oled-care \
    | tee "$DATA_DIR/macos-install.log" \
    || die "The macOS installer failed; see $DATA_DIR/macos-install.log"
  grep -q 'mac-tahoe\|mac\.tahoe' "$LOOK_CFG/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null \
    || die "The macOS layout didn't land in this look's settings; see $DATA_DIR/macos-install.log"
  # Menu bar, app colors, wallpaper and lock screen as on a real Tahoe Mac (also runs
  # before every Tahoe session: see before-session)
  python3 "$LOOK_DIR/tahoe-finish.py" "$LOOK_CFG" || warn "Couldn't finish the Tahoe menu bar"
  # Desktop icons line up down the right edge, as on a Mac
  look_run qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
    desktops().forEach(function (d) {
      d.currentConfigGroup = ['General']; d.writeConfig('arrangement', 1); d.writeConfig('alignment', 1); d.reloadConfig();
    });" >/dev/null || warn "Couldn't arrange the desktop icons"
}

look_remove() {
  [[ -d $MAC_SRC ]] || { ok "macOS Tahoe isn't installed."; return 0; }
  log "Removing macOS Tahoe (asks for your password)"
  SETUP_MODE=sandbox; cmd_sandbox macos start
  look_root env MTTKDE_NO_CONFIRM=1 MAC_TAHOE_NO_UPDATE_CHECK=true \
    python3 "$MAC_SRC/src/scripts/installer_backend.py" uninstall || warn "Its uninstaller reported a problem."
  cmd_sandbox macos stop
  rm -f "$LOOK_CFG/.ready"
  ok "Removed. Its settings tree stays in $LOOK_CFG (delete it if you like)."
}
