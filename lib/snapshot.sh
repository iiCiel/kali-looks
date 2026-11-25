# shellcheck shell=bash
# Save the desktop as it was before the first look, and put it back on `looks revert`.

# Config files (relative to ~/.config) that any look may change.
SNAPSHOT_FILES=(
  kdeglobals kwinrc kwinrulesrc plasmarc plasmashellrc plasma-org.kde.plasma.desktop-appletsrc
  kglobalshortcutsrc kcminputrc ksplashrc kscreenlockerrc krunnerrc dolphinrc konsolerc
  kservicemenurc kxkbrc breezerc auroraerc
  Kvantum/kvantum.kvconfig
  gtk-3.0/settings.ini gtk-4.0/settings.ini gtk-3.0/gtk.css gtk-4.0/gtk.css xsettingsd/xsettingsd.conf
  autostart/kali-looks-plank.desktop
  kdedefaults
)

snapshot_original() {
  [[ -f $ORIG_DIR/.done ]] && return 0
  log "Saving your current desktop (restore any time with: looks revert)"
  mkdir -p "$ORIG_DIR/config"
  : > "$ORIG_DIR/absent"
  local f
  for f in "${SNAPSHOT_FILES[@]}"; do
    if [[ -e $CONF_HOME/$f ]]; then
      mkdir -p "$ORIG_DIR/config/$(dirname "$f")"
      cp -a "$CONF_HOME/$f" "$ORIG_DIR/config/$f"
    else
      echo "$f" >> "$ORIG_DIR/absent"
    fi
  done
  if command -v dconf >/dev/null; then
    dconf dump /net/launchpad/plank/ > "$ORIG_DIR/plank.dconf" 2>/dev/null || true
  fi
  date -Is > "$ORIG_DIR/.done"
  ok "Saved to $ORIG_DIR"
}

restore_original() {
  [[ -f $ORIG_DIR/.done ]] || die "Nothing to restore: no look has been applied yet."
  local f
  for f in "${SNAPSHOT_FILES[@]}"; do
    if [[ -e $ORIG_DIR/config/$f ]]; then
      mkdir -p "$CONF_HOME/$(dirname "$f")"
      rm -rf "${CONF_HOME:?}/$f"
      cp -a "$ORIG_DIR/config/$f" "$CONF_HOME/$f"
    elif grep -qxF -- "$f" "$ORIG_DIR/absent"; then
      rm -rf "${CONF_HOME:?}/$f"
    fi
  done
  if [[ -f $ORIG_DIR/plank.dconf ]] && command -v dconf >/dev/null; then
    dconf reset -f /net/launchpad/plank/ 2>/dev/null || true
    if [[ -s $ORIG_DIR/plank.dconf ]]; then dconf load /net/launchpad/plank/ < "$ORIG_DIR/plank.dconf"; fi
  fi
  return 0
}
