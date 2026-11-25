# shellcheck shell=bash
# shellcheck disable=SC2034  # LOOK_* are read by the looks command
# Windows 7 look: AeroThemePlasma (https://github.com/aeroshell-desktop/aerothemeplasma),
# built from source at pinned versions. It is a separate login session, so "applying"
# it means building it once and then choosing "AeroThemePlasma" at the login screen.
#
# Heads-up: it installs its own build of Plasma's libplasma over the system one. A Kali
# update that upgrades libplasma replaces it again and the Windows 7 session needs a
# rebuild: `looks rebuild win7`. `looks remove win7` undoes everything.

LOOK_TITLE="Windows 7 (AeroThemePlasma)"
LOOK_VARIANTS=(aero)
LOOK_SESSION="aerothemeplasma"   # chosen at the login screen

# Pinned upstreams: "<dir> <url> <commit>"
W7_BRANCH="Plasma/6.7"
W7_REPOS=(
  "aerothemeplasma https://github.com/aeroshell-desktop/aerothemeplasma.git e4cca91b12dd9419485c19bece76534972324f6a"
  "libplasma https://gitgud.io/aeroshell/libplasma.git 6ed0921cfb5f55c7c3e7ebe38a890c69db49ec7d"
  "uac-polkit-agent https://gitgud.io/aeroshell/uac-polkit-agent.git d8c2262f5a12fe1a53560e70414b9312b91d84bb"
  "smod https://gitgud.io/aeroshell/smod.git ba963d7016295a8ca18cc7c60f0e73b62ba3e492"
  "aeroshell-workspace https://gitgud.io/aeroshell/aeroshell-workspace.git ad919f4cbf67cd0bedc5b7710b5b5738ce12d006"
  "aeroshell-kwin-components https://gitgud.io/aeroshell/aeroshell-kwin-components.git 461ba76c05e78680045fd36099addac68df0b50b"
  "aeroshell-sddm-kcm https://gitgud.io/aeroshell/aeroshell-sddm-kcm.git 8c94283c2689b3f0837efda0be8107e42a265e0f"
  "aerothemeplasma-icons https://gitgud.io/aeroshell/atp/aerothemeplasma-icons.git 0100536bb0fb4b731b6cf776f3bc6dc5d3c74bfc"
  "aerothemeplasma-sounds https://gitgud.io/aeroshell/atp/aerothemeplasma-sounds.git 55d2f5fd15f53cccbbb13388941b930442db1159"
)

W7_SRC="$SRC_DIR/win7"
W7_MANIFESTS="$DATA_DIR/win7-manifests"
W7_LIBEXEC="lib/$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo x86_64-linux-gnu)/libexec"

w7_deps() {
  local p
  for p in $(grep -v '^#' "$LOOK_DIR/deps.txt"); do apt_has "$p" && echo "$p"; done
  return 0
}

w7_installed() { [[ -f $W7_MANIFESTS/aerothemeplasma.txt ]]; }

# Build one CMake project as the normal user. $1 = source dir, $2 = build dir name, rest = cmake args
w7_build() {
  local src=$1 bdir=$2; shift 2
  log "Building $(basename "$src")${bdir:+ ($bdir)}"
  cmake -S "$src" -B "$src/$bdir" -G Ninja -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release "$@" \
    > "$W7_SRC/logs/$(basename "$src")-$bdir.cmake.log" 2>&1 \
    || die "Configuring $(basename "$src") failed; see $W7_SRC/logs/"
  cmake --build "$src/$bdir" -j"$(nproc)" > "$W7_SRC/logs/$(basename "$src")-$bdir.build.log" 2>&1 \
    || die "Building $(basename "$src") failed; see $W7_SRC/logs/$(basename "$src")-$bdir.build.log"
  W7_BUILDS+=("$src/$bdir")
}

w7_build_all() {
  mkdir -p "$W7_SRC/logs"
  W7_BUILDS=()
  local S="$W7_SRC"
  # Same order and options as AeroThemePlasma's install.sh (libplasma first)
  w7_build "$S/libplasma" build
  w7_build "$S/uac-polkit-agent" build -DCMAKE_INSTALL_LIBEXECDIR="$W7_LIBEXEC/kf6"
  w7_build "$S/smod" build
  w7_build "$S/smod" build-x11 -DBUILD_DECORATION=OFF -DBUILD_EFFECTX11=ON
  w7_build "$S/aeroshell-workspace" build
  w7_build "$S/aeroshell-kwin-components" build -DKWIN_BUILD_WAYLAND=ON
  w7_build "$S/aeroshell-kwin-components" build_x11 -DKWIN_BUILD_WAYLAND=OFF -DKWIN_INSTALL_MISC=OFF
  w7_build "$S/aeroshell-sddm-kcm" build
  w7_build "$S/aerothemeplasma-icons" build
  w7_build "$S/aerothemeplasma-sounds" build
  w7_build "$S/aerothemeplasma" build -DCMAKE_INSTALL_LIBEXECDIR="$W7_LIBEXEC"
  w7_build "$S/aerothemeplasma" build_x11 -DCMAKE_INSTALL_LIBEXECDIR="$W7_LIBEXEC" -DINSTALL_X11_COMPONENTS=ON
}

# Install every build in one root step (one password prompt), keeping each manifest.
w7_install_all() {
  local script="$W7_SRC/install-as-root.sh" b
  {
    echo "set -e"
    for b in "${W7_BUILDS[@]}"; do echo "cmake --install '$b'"; done
    echo "update-mime-database /usr/local/share/mime 2>/dev/null || true"
    echo "update-mime-database /usr/share/mime 2>/dev/null || true"
  } > "$script"
  log "Installing AeroThemePlasma (asks for your password)"
  as_root bash "$script" > "$W7_SRC/logs/install.log" 2>&1 || die "Installing failed; see $W7_SRC/logs/install.log"
  mkdir -p "$W7_MANIFESTS"
  for b in "${W7_BUILDS[@]}"; do
    [[ -f $b/install_manifest.txt ]] && cp "$b/install_manifest.txt" "$W7_MANIFESTS/$(basename "$(dirname "$b")")-$(basename "$b").txt"
  done
  cp "$W7_MANIFESTS/aerothemeplasma-build.txt" "$W7_MANIFESTS/aerothemeplasma.txt"
  dpkg-query -W -f='${Version}' libplasma7 > "$W7_MANIFESTS/libplasma-version" 2>/dev/null || true
}

look_prepare() {
  if w7_installed; then
    local built cur
    built=$(cat "$W7_MANIFESTS/libplasma-version" 2>/dev/null || true)
    cur=$(dpkg-query -W -f='${Version}' libplasma7 2>/dev/null || true)
    if [[ $built == "$cur" ]]; then ok "AeroThemePlasma is already built and installed"; return 0; fi
    warn "Plasma was updated since AeroThemePlasma was built ($built -> $cur); rebuilding."
  fi
  log "Windows 7 needs AeroThemePlasma built from source (about 10-30 minutes)."
  # shellcheck disable=SC2046
  need_packages $(w7_deps)
  local entry name url commit
  for entry in "${W7_REPOS[@]}"; do
    read -r name url commit <<<"$entry"
    SRC_DIR="$W7_SRC" fetch_repo "$name" "$url" "$commit"
  done
  w7_build_all
  w7_install_all
  ok "AeroThemePlasma installed"
}

w7_session_name() {
  local f
  for f in /usr/share/xsessions/*.desktop /usr/share/wayland-sessions/*.desktop; do
    grep -qi -E 'aero' "$f" 2>/dev/null && { basename "$f" .desktop; return 0; }
  done
  return 1
}

look_apply() {
  local session user_path
  session=$(w7_session_name) || die "AeroThemePlasma's login session wasn't found after installing."
  # Make it the session for the next login (the login screen remembers the choice)
  user_path="/org/freedesktop/Accounts/User$(id -u)"
  if busctl call org.freedesktop.Accounts "$user_path" org.freedesktop.Accounts.User SetXSession s "$session" 2>/dev/null; then
    ok "Next login starts the Windows 7 session ($session)."
  else
    warn "Couldn't preselect it: choose \"$session\" in the session menu at the login screen."
  fi
  echo "  Log out to switch. To come back, pick Plasma (or Xfce) at the login screen."
}

look_leave() {
  # Switching to another look from inside Plasma: just make the next login normal Plasma again.
  local s user_path
  user_path="/org/freedesktop/Accounts/User$(id -u)"
  for s in plasmax11 plasma; do
    [[ -f /usr/share/xsessions/$s.desktop || -f /usr/share/wayland-sessions/$s.desktop ]] || continue
    busctl call org.freedesktop.Accounts "$user_path" org.freedesktop.Accounts.User SetXSession s "$s" 2>/dev/null || true
    break
  done
}

# looks rebuild win7
look_rebuild() { rm -f "$W7_MANIFESTS/libplasma-version"; look_prepare; }

# looks remove win7: delete what was installed and put Kali's own packages back
look_remove() {
  w7_installed || { ok "AeroThemePlasma isn't installed."; return 0; }
  local f script="$W7_SRC/remove-as-root.sh"; local -a owned=()
  log "Working out which files belong to Kali packages"
  while IFS= read -r f; do
    [[ -e $f ]] || continue
    local pkg; pkg=$(dpkg -S "$f" 2>/dev/null | head -n 1 | cut -d: -f1) || true
    [[ -n $pkg ]] && owned+=("$pkg")
  done < <(cat "$W7_MANIFESTS"/*.txt | sort -u)
  mapfile -t owned < <(printf '%s\n' "${owned[@]}" | sort -u)
  {
    echo "set -e"
    echo "cat '$W7_MANIFESTS'/*.txt | sort -u | while IFS= read -r f; do"
    echo "  [ -e \"\$f\" ] || continue"
    echo "  dpkg -S \"\$f\" >/dev/null 2>&1 || rm -f \"\$f\""
    echo "done"
    if [[ ${#owned[@]} -gt 0 ]]; then
      echo "DEBIAN_FRONTEND=noninteractive apt-get install -y --reinstall ${owned[*]}"
    fi
    echo "update-mime-database /usr/local/share/mime 2>/dev/null || true"
  } > "$script"
  log "Removing AeroThemePlasma and reinstalling ${#owned[@]} Kali packages it replaced (asks for your password)"
  as_root bash "$script" || die "Removing failed."
  rm -rf "$W7_MANIFESTS"
  look_leave
  ok "AeroThemePlasma removed."
}
