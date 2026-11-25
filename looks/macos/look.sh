# shellcheck shell=bash
# shellcheck disable=SC2034  # LOOK_* are read by the looks command
# macOS Tahoe: "macOS Tahoe Shell for KDE" by Lester Cordero Murillo and contributors
# (https://github.com/lestercorderomurillo/macos-tahoe-liquid-kde, GPL-3.0): menu bar
# with global menus and Control Center, Liquid Glass dock, Launchpad, Finder look,
# SF Pro fonts, Tahoe icons/cursors/wallpapers, rounded window corners.
# Its own installer does the work; kali-looks points it at this look's config tree and
# leaves out the parts that would reach outside this session (Firefox, login and boot screens).

LOOK_TITLE="macOS Tahoe"
MAC_REPO="https://github.com/lestercorderomurillo/macos-tahoe-liquid-kde.git"
MAC_COMMIT="aa482a96a689694564d0cec22987e35291274afb"   # 0.85.2
MAC_SRC="$SRC_DIR/macos-tahoe"

look_prepare() {
  need_packages python3-pyqt6
  if [[ -d $MAC_SRC/.git ]] && [[ $(git -C "$MAC_SRC" rev-parse HEAD 2>/dev/null) == "$MAC_COMMIT" ]]; then return 0; fi
  log "Downloading macOS Tahoe Shell for KDE"
  rm -rf "$MAC_SRC"
  git clone -q --filter=blob:none "$MAC_REPO" "$MAC_SRC" || die "Couldn't download it."
  git -C "$MAC_SRC" checkout -q "$MAC_COMMIT" || die "Couldn't check out the tested version."
}

look_setup() {
  log "Installing macOS Tahoe into its session (asks for your password; takes a few minutes)"
  # shellcheck disable=SC2016
  look_root env MTTKDE_NO_CONFIRM=1 MAC_TAHOE_NO_UPDATE_CHECK=true MTTKDE_NO_GRUB_MODIFY=1 \
    python3 "$MAC_SRC/src/scripts/installer_backend.py" install --light \
      --no-firefox --no-sddm --no-plymouth --no-nautilus --no-nautilus-bookmarks --no-oled-care \
    | tee "$DATA_DIR/macos-install.log" \
    || die "The macOS installer failed; see $DATA_DIR/macos-install.log"
  grep -q 'mac-tahoe\|mac\.tahoe' "$LOOK_CFG/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null \
    || die "The macOS layout didn't land in this look's settings; see $DATA_DIR/macos-install.log"
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
