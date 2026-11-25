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

# Everything that needs root happens in one script (one password prompt): install the
# build dependencies, then for each component compile it AS YOU (runuser) and install it
# as root right away (later components build against earlier ones), keeping manifests.
w7_steps() {
  local S="$W7_SRC"
  # name|source|build dir|extra cmake args  (same order and options as upstream install.sh)
  cat <<EOF
libplasma|$S/libplasma|build|
uac-polkit-agent|$S/uac-polkit-agent|build|-DCMAKE_INSTALL_LIBEXECDIR=$W7_LIBEXEC/kf6
smod|$S/smod|build|
smod|$S/smod|build-x11|-DBUILD_DECORATION=OFF -DBUILD_EFFECTX11=ON
aeroshell-workspace|$S/aeroshell-workspace|build|
aeroshell-kwin-components|$S/aeroshell-kwin-components|build|-DKWIN_BUILD_WAYLAND=ON
aeroshell-kwin-components|$S/aeroshell-kwin-components|build_x11|-DKWIN_BUILD_WAYLAND=OFF -DKWIN_INSTALL_MISC=OFF
aeroshell-sddm-kcm|$S/aeroshell-sddm-kcm|build|
aerothemeplasma-icons|$S/aerothemeplasma-icons|build|
aerothemeplasma-sounds|$S/aerothemeplasma-sounds|build|
aerothemeplasma|$S/aerothemeplasma|build|-DCMAKE_INSTALL_LIBEXECDIR=$W7_LIBEXEC
aerothemeplasma|$S/aerothemeplasma|build_x11|-DCMAKE_INSTALL_LIBEXECDIR=$W7_LIBEXEC -DINSTALL_X11_COMPONENTS=ON
EOF
}

w7_root_script() {
  local -a missing=(); local p
  for p in $(w7_deps); do pkg_installed "$p" || missing+=("$p"); done
  cat <<EOF
#!/bin/bash
set -euo pipefail
U='$(id -un)'
LOGS='$W7_SRC/logs'
MAN='$W7_MANIFESTS'
EOF
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "echo '==> Installing ${#missing[@]} build dependencies'"
    echo "DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ${missing[*]} > \"\$LOGS/deps.log\" 2>&1 || { echo 'error: installing build dependencies failed; see '\"\$LOGS/deps.log\"; exit 1; }"
  fi
  cat <<'EOF'
# Compile with the GCC that matches the system's C++ runtime (Kali can be mid-transition:
# libraries built with a newer GCC than the default g++).
GCCV=$(dpkg-query -W -f='${Version}' libstdc++6 | sed -E 's/^[0-9]+://; s/\..*//')
if [[ $GCCV =~ ^[0-9]+$ ]] && ! command -v "g++-$GCCV" >/dev/null; then
  echo "==> Installing g++-$GCCV (matches the system C++ library)"
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "g++-$GCCV" > "$LOGS/gcc.log" 2>&1 \
    || { echo "error: installing g++-$GCCV failed; see $LOGS/gcc.log"; exit 1; }
fi
CCX="CC=gcc CXX=g++"
command -v "g++-$GCCV" >/dev/null && CCX="CC=gcc-$GCCV CXX=g++-$GCCV"
runuser -u "$U" -- mkdir -p "$MAN"
while IFS='|' read -r name src bdir args; do
  [[ -n $name ]] || continue
  echo "==> Building $name ($bdir)"
  log="$LOGS/$name-$bdir.log"
  # shellcheck disable=SC2086
  # a build dir configured with another compiler can't be reused
  if [[ -f $src/$bdir/CMakeCache.txt ]] && ! grep -q "CMAKE_CXX_COMPILER:.*g++-$GCCV" "$src/$bdir/CMakeCache.txt"; then
    runuser -u "$U" -- rm -rf "$src/$bdir"
  fi
  runuser -u "$U" -- env $CCX bash -c "cmake -S '$src' -B '$src/$bdir' -G Ninja -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF $args > '$log' 2>&1 && cmake --build '$src/$bdir' -j\$(nproc) >> '$log' 2>&1" \
    || { echo "error: building $name failed; see $log"; exit 1; }
  cmake --install "$src/$bdir" >> "$LOGS/install.log" 2>&1 || { echo "error: installing $name failed; see $LOGS/install.log"; exit 1; }
  cp "$src/$bdir/install_manifest.txt" "$MAN/$name-$bdir.txt"
  chown "$U": "$src/$bdir/install_manifest.txt" "$MAN/$name-$bdir.txt"
done < "$LOGS/steps.txt"
update-mime-database /usr/local/share/mime 2>/dev/null || true
update-mime-database /usr/share/mime 2>/dev/null || true
echo "==> Done"
EOF
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
  need_packages git curl
  local entry name url commit
  for entry in "${W7_REPOS[@]}"; do
    read -r name url commit <<<"$entry"
    SRC_DIR="$W7_SRC" fetch_repo "$name" "$url" "$commit"
  done
  # Upstream may require a newer Plasma point release than the distro ships yet (e.g.
  # 6.7.5 vs 6.7.4). Those bumps are version numbers only, so ask for what's installed.
  local pv f
  pv=$(dpkg-query -W -f='${Version}' plasma-workspace 2>/dev/null | sed -E 's/^[0-9]+://; s/[-+~].*//')
  if [[ $pv =~ ^6\.[0-9]+\.[0-9]+$ ]]; then
    while IFS= read -r -d '' f; do
      sed -i -E '/find_package\(/ s/\$\{PROJECT_(DEP_)?VERSION\}/'"$pv"'/g' "$f"
    done < <(find "$W7_SRC" -name CMakeLists.txt -not -path '*/build*' -print0)
  fi
  mkdir -p "$W7_SRC/logs"
  w7_steps > "$W7_SRC/logs/steps.txt"
  w7_root_script > "$W7_SRC/build-and-install.sh"
  log "Building and installing AeroThemePlasma (asks for your password once; compiling runs as you)"
  as_root bash "$W7_SRC/build-and-install.sh" || die "AeroThemePlasma didn't build; see the log named above."
  cp "$W7_MANIFESTS/aerothemeplasma-build.txt" "$W7_MANIFESTS/aerothemeplasma.txt"
  dpkg-query -W -f='${Version}' libplasma7 > "$W7_MANIFESTS/libplasma-version" 2>/dev/null || true
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
