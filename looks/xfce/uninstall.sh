#!/usr/bin/env bash
# cupertino-xfce uninstaller: puts back what install.sh changed, from its backups.
#
#   ./uninstall.sh                 restore your desktop as it was before the FIRST install
#   ./uninstall.sh --backup DIR    restore from one specific backup only
#   ./uninstall.sh --purge         also delete the themes, wallpapers and added packages
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

BACKUP=""; PURGE=0; ASSUME_YES=0
usage() {
  cat <<EOF
Usage: ./uninstall.sh [--backup DIR] [--purge] [-y]

  --backup DIR   Restore from this backup only (default: walk every backup in
                 $BACKUP_ROOT so your original, pre-install settings win)
  --purge        Also remove the WhiteSur theme/icons/cursors, the wallpapers and the
                 packages the installer added
  -y, --yes      Don't ask for confirmation
EOF
}
while [[ $# -gt 0 ]]; do
  case $1 in
    --backup) BACKUP=${2:-}; shift ;;
    --purge) PURGE=1 ;;
    -y|--yes) ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
  shift
done

require_xfce_session
if [[ -n $BACKUP ]]; then
  [[ -f $BACKUP/info ]] || die "$BACKUP doesn't look like a cupertino-xfce backup."
  BACKUPS=("$BACKUP")
else
  mapfile -t BACKUPS < <(find "$BACKUP_ROOT" -mindepth 2 -maxdepth 2 -name info -printf '%h\n' 2>/dev/null | sort)
  [[ ${#BACKUPS[@]} -gt 0 ]] || die "No backup found in $BACKUP_ROOT. Nothing to restore."
fi
OLDEST=${BACKUPS[0]}
# First (oldest) backup that has a given file = the state before cupertino-xfce touched it.
first_with() { local b; for b in "${BACKUPS[@]}"; do [[ -e $b/$1 ]] && { printf '%s\n' "$b"; return 0; }; done; return 1; }
any_with() { local b; for b in "${BACKUPS[@]}"; do [[ -e $b/$1 ]] && return 0; done; return 1; }
INI_PY="$HERE/lib/ini-set.py"

echo "Restoring from ${#BACKUPS[@]} backup(s), oldest: $OLDEST"
[[ $PURGE -eq 1 ]] && echo "Also removing themes, wallpapers and added packages (--purge)."
if [[ $ASSUME_YES -eq 0 ]]; then
  if [[ -t 0 ]]; then
    read -rp "Continue? [y/N] " ans
    [[ $ans =~ ^[Yy] ]] || { echo "Cancelled."; exit 0; }
  else
    die "No terminal to confirm in. Re-run with --yes to proceed."
  fi
fi

# 1. Effects and helpers
log "Stopping picom"
if grep -qs '^X-Cupertino-Xfce=true' "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/picom.desktop"; then
  rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/picom.desktop"
fi
rm -f "$AUTOSTART_PICOM" "$AUTOSTART_PLANK" "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/cupertino-xfce-once.desktop"
pkill -u "$(id -u)" -x plank 2>/dev/null || true
pkill -u "$(id -u)" -f "picom --config $CONF_DIR/picom.conf" 2>/dev/null || true
pkill -u "$(id -u)" -f cupertino-control-center 2>/dev/null || true
pkill -u "$(id -u)" -f 'python3 .*cupertino-menu[d]' 2>/dev/null || true

# 2. xfconf settings: replay newest backup -> oldest, so the original values win.
log "Restoring settings"
for ((i = ${#BACKUPS[@]} - 1; i >= 0; i--)); do
  tsv="${BACKUPS[$i]}/xfconf.tsv"
  [[ -f $tsv ]] || continue
  while IFS=$'\t' read -r ch prop type existed val; do
    [[ -n $ch ]] || continue
    if [[ $existed == 1 ]]; then
      xset_prop "$ch" "$prop" "$type" "$val" || warn "couldn't restore $ch $prop"
    else
      xfconf-query -c "$ch" -p "$prop" -r 2>/dev/null || true
    fi
  done < "$tsv"
done
# Monitors connected after install got our wallpaper without a recorded original:
# hand them back to the default
while IFS= read -r k; do
  v=$(xfconf-query -c xfce4-desktop -p "$k" 2>/dev/null || true)
  [[ $v == *"/backgrounds/cupertino-xfce/"* ]] && xfconf-query -c xfce4-desktop -p "$k" -r 2>/dev/null
done < <(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep -E '/last-image$' || true)
# INI files (qterminal.ini, gtk-3.0/settings.ini), same order
for ((i = ${#BACKUPS[@]} - 1; i >= 0; i--)); do
  tsv="${BACKUPS[$i]}/ini.tsv"
  [[ -f $tsv ]] || continue
  while IFS=$'\t' read -r file sec key existed val; do
    [[ -n $file ]] || continue
    if [[ $existed == 1 ]]; then python3 "$INI_PY" "$file" "$sec" "$key" "$val" >/dev/null
    else python3 "$INI_PY" "$file" "$sec" "$key" --delete >/dev/null
    fi
  done < "$tsv"
done
ok "Theme, fonts, wallpaper, shortcuts, terminal and window settings restored"

# 3. Panels
if PB=$(first_with panel.tar.bz2); then
  log "Restoring your panels"
  xfce4-panel-profiles load "$PB/panel.tar.bz2" >/dev/null 2>&1 || warn "Couldn't reload your panel layout; open Panel Profiles to pick one."
  sleep 2
  pgrep -u "$(id -u)" -x xfce4-panel >/dev/null || { setsid xfce4-panel >/dev/null 2>&1 < /dev/null & }
  ok "Panels restored"
fi

# 3b. Plank: put back its settings as they were before the first install
if command -v dconf >/dev/null && PD=$(first_with plank.dconf); then
  dconf reset -f /net/launchpad/plank/ 2>/dev/null || true
  [[ -s $PD/plank.dconf ]] && dconf load /net/launchpad/plank/ < "$PD/plank.dconf"
  if [[ ! -s $PD/plank.dconf ]]; then rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/plank/dock1/launchers"; fi
fi
# the extra docks (one per monitor): stop them, forget their settings, remove their folders
for p in $(pgrep -u "$(id -u)" -f '(^|/)plank -n dock-' || true); do kill "$p" 2>/dev/null || true; done
if command -v dconf >/dev/null; then
  for d in $(dconf list /net/launchpad/plank/docks/ 2>/dev/null | sed -n 's#^\(dock-[A-Za-z0-9-]*\)/$#\1#p'); do
    dconf reset -f "/net/launchpad/plank/docks/$d/" 2>/dev/null || true
  done
fi
for d in "${XDG_CONFIG_HOME:-$HOME/.config}"/plank/dock-*; do
  [[ -L $d/launchers ]] && rm -rf "$d"
done
rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/plank/themes/Cupertino-Light" "${XDG_DATA_HOME:-$HOME/.local/share}/plank/themes/Cupertino-Dark"

# 4. Firefox: put back each profile's own chrome folder and user.js
FC="$DATA_DIR/firefox/chrome"
for b in "${BACKUPS[@]}"; do
  [[ -f $b/firefox/profiles.txt ]] || continue
  while IFS= read -r prof; do
    [[ -d $prof ]] || continue
    name=$(basename "$prof")
    orig=$(first_with "firefox/$name/chrome" 2>/dev/null || true)
    if [[ -L $prof/chrome && $(readlink "$prof/chrome") == "$FC" ]]; then rm -f "$prof/chrome"; fi
    if [[ -n $orig && ! -e $prof/chrome ]]; then mv "$orig/firefox/$name/chrome" "$prof/chrome"; fi
    if ub=$(first_with "firefox/$name/user.js"); then cp -a "$ub/firefox/$name/user.js" "$prof/user.js"
    elif first_with "firefox/$name/no-user.js" >/dev/null; then rm -f "$prof/user.js"
    else sed -i '/>>> cupertino-xfce/,/<<< cupertino-xfce/d' "$prof/user.js" 2>/dev/null || true
    fi
  done < "$b/firefox/profiles.txt"
done

# 5. Files we added
strip_block "$GTK_CSS"
for f in org.xfce.xfdesktop.desktop xfdesktop.desktop; do
  dst="$(dirname "$LAUNCHPAD_DESKTOP")/$f"
  grep -qs 'X-Cupertino-Xfce=true' "$dst" && rm -f "$dst"
done
rm -f "$LAUNCHPAD_DESKTOP" "$AUTOSTART_MENUD" "$HOME/.local/bin/cupertino-xfce-mode" "$HOME/.local/bin/cupertino-control-center" "$HOME/.local/bin/cupertino-menud"
rm -rf "$CONF_DIR" "$HOME/.themes/Cupertino-Notify" "$DATA_DIR/app" "$DATA_DIR/firefox"
rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps/cupertino-control-center-symbolic.svg"

# 6. System styling (root): login screen, terminal colour schemes, boot splash
R="$(mktemp)"; echo "set -e" > "$R"
if LB=$(first_with lightdm-gtk-greeter.conf) && any_with login.applied; then
  echo "cp \"$LB/lightdm-gtk-greeter.conf\" \"$GREETER_CONF\"" >> "$R"
  echo "rm -rf /usr/share/themes/WhiteSur-Login /usr/share/backgrounds/cupertino-xfce" >> "$R"
  [[ $PURGE -eq 1 ]] && echo "rm -rf /usr/share/icons/WhiteSur /usr/share/icons/WhiteSur-cursors" >> "$R"
fi
if QB=$(first_with qtermwidget-dir); then
  qd=$(cat "$QB/qtermwidget-dir")
  echo "rm -f \"$qd/Cupertino-Light.colorscheme\" \"$qd/Cupertino-Dark.colorscheme\"" >> "$R"
fi
if any_with boot.applied && BB=$(first_with plymouth.theme); then
  old=$(cat "$BB/plymouth.theme"); old=${old:-text}
  echo "plymouth-set-default-theme -R \"$old\"" >> "$R"
  echo "rm -rf /usr/share/plymouth/themes/cupertino" >> "$R"
fi
if [[ $(wc -l < "$R") -gt 1 ]]; then
  log "Restoring the login screen and boot splash (you'll be asked for your password)"
  if as_root_script "$R"; then ok "Login screen, terminal schemes and boot splash restored"
  else warn "Couldn't restore some system files. Originals are in $OLDEST"; fi
fi
rm -f "$R"

# 7. Purge
if [[ $PURGE -eq 1 ]]; then
  log "Removing themes, icons, cursors and wallpapers"
  rm -rf "$HOME/.themes/WhiteSur-Light" "$HOME/.themes/WhiteSur-Dark" \
         "${XDG_DATA_HOME:-$HOME/.local/share}/icons/WhiteSur" "${XDG_DATA_HOME:-$HOME/.local/share}/icons/WhiteSur-light" \
         "$HOME/.icons/WhiteSur-cursors" "${XDG_DATA_HOME:-$HOME/.local/share}/backgrounds/cupertino-xfce" "$SRC_DIR"
  mapfile -t pkgs < <(cat "${BACKUPS[@]/%//packages-added.txt}" 2>/dev/null | sort -u | sed '/^$/d')
  if [[ ${#pkgs[@]} -gt 0 ]]; then
    log "Removing the packages the installer added"
    R="$(mktemp)"
    { echo "set -e"; printf 'DEBIAN_FRONTEND=noninteractive apt-get remove -y'; printf ' %q' "${pkgs[@]}"; echo; } > "$R"
    as_root_script "$R" || warn "Package removal failed; remove them yourself: ${pkgs[*]}"
    rm -f "$R"
  fi
fi

cat <<EOF

${C_GRN}Done.${C_OFF} Your previous desktop is back.
Log out and back in to finish (some apps keep the old menu style until restarted).
Restart Firefox to drop its theme. Backups are kept in $BACKUP_ROOT.
EOF
