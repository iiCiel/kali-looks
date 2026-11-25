# shellcheck shell=bash
# Saved copies of the desktop's settings: the original (before the first look, for
# `looks revert`) and one profile per login session (lib/sessions.sh).

# Config files and folders (relative to ~/.config) that a look may change.
SNAPSHOT_FILES=(
  kdeglobals kwinrc kwinrulesrc plasmarc plasmashellrc plasma-org.kde.plasma.desktop-appletsrc
  kglobalshortcutsrc kcminputrc ksplashrc kscreenlockerrc krunnerrc dolphinrc konsolerc
  kservicemenurc kxkbrc breezerc auroraerc aerothemeplasmarc
  Kvantum/kvantum.kvconfig
  gtk-3.0/settings.ini gtk-4.0/settings.ini gtk-3.0/gtk.css gtk-4.0/gtk.css
  gtk-3.0/colors.css gtk-4.0/colors.css xsettingsd/xsettingsd.conf
  autostart/kali-looks-plank.desktop
  kdedefaults
)

# Copy the live settings into $1 (a folder), remembering which ones didn't exist.
save_set() {
  local dir=$1 f
  rm -rf "$dir"; mkdir -p "$dir/config"
  : > "$dir/absent"
  for f in "${SNAPSHOT_FILES[@]}"; do
    if [[ -e $CONF_HOME/$f ]]; then
      mkdir -p "$dir/config/$(dirname "$f")"
      cp -a "$CONF_HOME/$f" "$dir/config/$f"
    else
      echo "$f" >> "$dir/absent"
    fi
  done
  if command -v dconf >/dev/null; then
    dconf dump /net/launchpad/plank/ > "$dir/plank.dconf" 2>/dev/null || true
  fi
  date -Is > "$dir/.done"
}

# Make the live settings what's saved in $1. Returns 1 if nothing is saved there.
restore_set() {
  local dir=$1 f
  [[ -f $dir/.done ]] || return 1
  for f in "${SNAPSHOT_FILES[@]}"; do
    if [[ -e $dir/config/$f ]]; then
      mkdir -p "$CONF_HOME/$(dirname "$f")"
      rm -rf "${CONF_HOME:?}/$f"
      cp -a "$dir/config/$f" "$CONF_HOME/$f"
    elif grep -qxF -- "$f" "$dir/absent" 2>/dev/null; then
      rm -rf "${CONF_HOME:?}/$f"
    fi
  done
  if [[ -f $dir/plank.dconf ]] && command -v dconf >/dev/null; then
    dconf reset -f /net/launchpad/plank/ 2>/dev/null || true
    if [[ -s $dir/plank.dconf ]]; then dconf load /net/launchpad/plank/ < "$dir/plank.dconf"; fi
  fi
  return 0
}

snapshot_original() {
  [[ -f $ORIG_DIR/.done ]] && return 0
  log "Saving your current desktop (restore any time with: looks revert)"
  save_set "$ORIG_DIR"
  ok "Saved to $ORIG_DIR"
}

restore_original() {
  restore_set "$ORIG_DIR" || die "Nothing to restore: no look has been applied yet."
}
