# shellcheck shell=bash
# shellcheck disable=SC2034  # LOOK_* are read by the looks command
# Windows XP: XPlasma Plus (https://github.com/ergosteur/XPlasma-Plus, GPL-3.0; a fork of
# hotsocket's XPlasma, https://tangled.org/hotsocket.fyi/xplasma). It renders XP's real
# Luna visual style: taskbar, Start menu, tray, window borders, Qt and GTK controls,
# fonts, icons, pointers, sounds, Bliss, logout and lock screens.
# Its installer runs inside this look's session, so everything it changes stays there.
# Left out: its login screen (SDDM; Kali uses LightDM), boot splash and the IE6 Firefox.

LOOK_TITLE="Windows XP"
XP_VERSION="1.0.4-beta.2"
XP_URL="https://github.com/ergosteur/XPlasma-Plus/releases/download/v$XP_VERSION/xplasma-plus-$XP_VERSION-installer-generic.tar.gz"
XP_SHA256="e222821f67091a0362ba91384cb9c2fc77ee854dc0a6dcfe7def43b27345f8fc"
XP_SRC="$SRC_DIR/xplasma-plus-$XP_VERSION"
XP_FEATURES="theme_manager,desktop,apps,fonts,taskbar,icons,pointers,sounds,wallpaper,behavior,caption_animation,desktop_icons,session,welcome_splash,lock"

xp_backend() { find "$XP_SRC" -maxdepth 3 -name backend.py -path '*installer*' | head -1; }

look_prepare() {
  need_packages pkexec python3
  [[ -n $(xp_backend) ]] && return 0
  local tgz="$DL_DIR/${XP_URL##*/}"
  if ! sha_ok "$tgz" "$XP_SHA256" 2>/dev/null; then
    log "Downloading XPlasma Plus $XP_VERSION (about 500 MB)"
    curl -fL --retry 3 -o "$tgz" "$XP_URL" || die "Couldn't download XPlasma Plus."
    sha_ok "$tgz" "$XP_SHA256" || die "The XPlasma Plus download doesn't match its published checksum."
  fi
  rm -rf "$XP_SRC"; mkdir -p "$XP_SRC"
  tar -xzf "$tgz" -C "$XP_SRC" || die "Couldn't unpack XPlasma Plus."
  [[ -n $(xp_backend) ]] || die "XPlasma Plus' installer wasn't where expected in the archive."
}

look_setup() {
  local be; be=$(xp_backend)
  log "Installing Windows XP into its session (asks for your password; compiling takes ~10 minutes)"
  ( cd "$(dirname "$be")" && look_run python3 "$be" install --features="$XP_FEATURES" --theme 'Luna Blue' --tweaks= ) \
    2>&1 | tee "$DATA_DIR/winxp-install.log"
  [[ ${PIPESTATUS[0]} -eq 0 ]] || die "The XP installer failed; see $DATA_DIR/winxp-install.log"
}

look_remove() {
  local be; be=$(xp_backend)
  [[ -n $be ]] || { ok "Windows XP isn't installed."; return 0; }
  log "Removing Windows XP (asks for your password)"
  SETUP_MODE=sandbox; cmd_sandbox winxp start
  ( cd "$(dirname "$be")" && look_run python3 "$be" uninstall ) || warn "Its uninstaller reported a problem."
  cmd_sandbox winxp stop
  rm -f "$LOOK_CFG/.ready"
  ok "Removed."
}
