# shellcheck shell=bash
# shellcheck disable=SC2034  # LOOK_* are read by the looks command
# Windows 7: AeroThemePlasma (https://github.com/aeroshell-desktop/aerothemeplasma, AGPL-3.0),
# built from source at pinned versions. Its session (startatp) runs its own first-login
# setup in this look's fresh config tree.
#
# Heads-up: it installs its own build of Plasma's libplasma over the system one. A Kali
# update that upgrades libplasma replaces it again and the Windows 7 session needs a
# rebuild: `looks rebuild win7`. `looks remove win7` undoes everything.

LOOK_TITLE="Windows 7"

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
# with kali-looks' own "Windows 7" session installed, keep AeroThemePlasma's duplicates hidden
if [ -f /usr/share/xsessions/kali-looks-win7.desktop ]; then
  for f in /usr/share/xsessions/aerothemeplasmax11.desktop /usr/share/wayland-sessions/aerothemeplasma.desktop; do
    [ -f "$f" ] && ! grep -q '^NoDisplay=true' "$f" && echo 'NoDisplay=true' >> "$f"
  done
fi
echo "==> Done"
EOF
}

w7_build() {
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

look_prepare() { w7_build; }

# First login: AeroThemePlasma's own setup runs in the fresh session. Do it now in the
# hidden session so the real first login is already finished.
w7_setup() {
  local i
  for i in $(seq 90); do
    [[ -n $(kreadconfig6 --file "$LOOK_CFG/kdeglobals" --group KDE --key LookAndFeelPackage 2>/dev/null) ]] && break
    sleep 2
  done
}

look_setup() { w7_setup; }

# looks rebuild win7
look_rebuild() { rm -f "$W7_MANIFESTS/libplasma-version"; w7_build; }

# looks remove win7: delete what was installed and put Kali's own packages back
look_remove() {
  w7_installed || { ok "AeroThemePlasma isn't installed."; return 0; }
  local man="$W7_SRC/installed-files.txt" pk="$W7_SRC/replaced-packages.txt" script="$W7_SRC/remove-as-root.sh"
  cat "$W7_MANIFESTS"/*-build*.txt | sort -u > "$man"
  # the same paths as dpkg may list them on a merged-/usr system (/lib/... for /usr/lib/...)
  { cat "$man"; sed -E 's#^/usr/(lib|lib64|bin|sbin)/#/\1/#' "$man"; } | sort -u > "$man.both"
  # Packages whose files it overwrote (e.g. libplasma7): reinstall them afterwards
  grep -l -x -F -f "$man.both" /var/lib/dpkg/info/*.list 2>/dev/null \
    | xargs -r -n1 basename | sed 's/\.list$//; s/:.*//' | sort -u > "$pk"
  cat > "$script" <<EOF
#!/bin/bash
set -euo pipefail
# delete what isn't a Kali package's file
# (dpkg may list /lib/... for /usr/lib/... on merged-/usr systems: count both)
cat /var/lib/dpkg/info/*.list | sed -E 'p; s#^/(lib|lib64|bin|sbin)/#/usr/\\1/#' | sort -u > /tmp/kali-looks-dpkg-files.txt
grep -v -x -F -f /tmp/kali-looks-dpkg-files.txt '$man' | while IFS= read -r f; do rm -f -- "\$f"; done
rm -f /tmp/kali-looks-dpkg-files.txt
if [ -s '$pk' ]; then
  DEBIAN_FRONTEND=noninteractive apt-get install -y --reinstall \$(cat '$pk')
fi
update-mime-database /usr/local/share/mime 2>/dev/null || true
EOF
  log "Removing AeroThemePlasma ($(wc -l < "$man") files) and reinstalling: $(tr '\n' ' ' < "$pk")(asks for your password)"
  as_root bash "$script" || die "Removing failed."
  rm -rf "$W7_MANIFESTS"
  rm -f "$LOOK_CFG/.ready"
  ok "AeroThemePlasma removed. Log out and back in."
}
