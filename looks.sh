#!/usr/bin/env bash
# looks: switch KDE Plasma between whole-desktop looks (macOS, Windows XP, Windows 7).
#
#   looks list                     show the looks and which one is active
#   looks apply <look> [variant]   e.g. looks apply macos dark | looks apply winxp
#   looks revert                   put your desktop back the way it was
#   looks install                  install the `looks` command into ~/.local/bin
#   looks help
set -Eeuo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=lib/snapshot.sh
source "$HERE/lib/snapshot.sh"

all_looks() { local d; for d in "$HERE"/looks/*/; do [[ -f $d/look.sh ]] && basename "$d"; done; }

load_look() {
  local id=$1
  LOOK_DIR="$HERE/looks/$id"
  [[ -f $LOOK_DIR/look.sh ]] || die "Unknown look '$id'. Try: looks list"
  export LOOK_ID=$id
  # shellcheck source=/dev/null
  source "$LOOK_DIR/look.sh"
}

# Undo the running parts of the current look (its dock, autostart entries) before
# another look takes over. Config files are simply overwritten by the next look.
leave_current() {
  local cur; cur=$(state_get LOOK || true)
  [[ -n $cur && -d $HERE/looks/$cur ]] || return 0
  ( load_look "$cur"; if declare -F look_leave >/dev/null; then look_leave; fi )
}

cmd_list() {
  local cur id variant title; cur=$(state_get LOOK || true); variant=$(state_get VARIANT || true)
  echo "Looks:"
  for id in $(all_looks); do
    title=$( (load_look "$id"; echo "$LOOK_TITLE") )
    if [[ $id == "$cur" ]]; then
      printf '  %s* %-8s%s %s (active%s)\n' "$C_GRN" "$id" "$C_OFF" "$title" "${variant:+, $variant}"
    else
      printf '    %-8s %s\n' "$id" "$title"
    fi
  done
  [[ -n $cur ]] || echo "  (none active: Plasma's own look)"
}

cmd_apply() {
  local id=${1:-} variant=${2:-}
  [[ -n $id ]] || die "Which look? Try: looks list"
  load_look "$id"
  [[ -n $variant ]] || variant=${LOOK_VARIANTS[0]:-default}
  if [[ ${#LOOK_VARIANTS[@]} -gt 0 ]] && ! printf '%s\n' "${LOOK_VARIANTS[@]}" | grep -qxF -- "$variant"; then
    die "$LOOK_TITLE has no '$variant' variant (try: ${LOOK_VARIANTS[*]})"
  fi
  if [[ -z $LOOK_SESSION ]] && ! in_plasma; then
    die "Run this inside a KDE Plasma session (log in to Plasma, then run it from a terminal)."
  fi
  mkdir -p "$DATA_DIR" "$CONF_DIR" "$SRC_DIR"
  snapshot_original
  look_prepare
  leave_current
  load_look "$id"
  look_apply "$variant"
  state_set LOOK "$id"
  state_set VARIANT "$variant"
}

cmd_revert() {
  leave_current
  log "Restoring your desktop as it was before the first look"
  restore_original
  local orig_lnf
  orig_lnf=$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage 2>/dev/null || true)
  if in_plasma; then
    restart_plasmashell
    reconfigure_kwin
  fi
  state_set LOOK ""
  state_set VARIANT ""
  ok "Back to your own desktop${orig_lnf:+ ($orig_lnf)}. Log out and back in to reset everything."
}

cmd_install() {
  mkdir -p "$BIN_DIR"
  ln -sf "$HERE/looks.sh" "$BIN_DIR/looks"
  ok "Installed: $BIN_DIR/looks  (make sure $BIN_DIR is on your PATH)"
}

usage() { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; }

case "${1:-help}" in
  list|ls) cmd_list ;;
  apply|use) shift; cmd_apply "$@" ;;
  revert|reset) cmd_revert ;;
  install) cmd_install ;;
  status) echo "$(state_get LOOK || true) $(state_get VARIANT || true)" ;;
  -h|--help|help) usage ;;
  --version) echo "looks $LOOKS_VERSION" ;;
  *) usage; exit 2 ;;
esac
