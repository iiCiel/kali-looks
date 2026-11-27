#!/bin/bash
# kali-looks: Windows 7's taskbar menu window arrangements, done by KWin.
#   arrange.sh cascade|stack|side
# Cascade windows / Show windows stacked / Show windows side by side: the open
# (not minimized) windows on each screen, as Windows 7 arranges them.
mode=${1:-cascade}
case "$mode" in cascade|stack|side) ;; *) echo "usage: $0 cascade|stack|side" >&2; exit 2 ;; esac
f=$(mktemp --suffix=.js)
trap 'rm -f "$f"' EXIT
cat >"$f" <<EOF
const mode = "$mode";
for (const out of workspace.screens) {
    const area = workspace.clientArea(KWin.MaximizeArea, out, workspace.currentDesktop);
    const wins = workspace.stackingOrder.filter(w => w.normalWindow && !w.minimized && !w.skipTaskbar
        && w.output === out && (w.onAllDesktops || w.desktops.indexOf(workspace.currentDesktop) >= 0));
    const n = wins.length;
    if (!n) continue;
    wins.forEach((w, i) => {
        w.setMaximize(false, false);
        let r;
        if (mode === "cascade") {
            const step = 26, wd = Math.round(area.width * 0.6), ht = Math.round(area.height * 0.6);
            const k = i % Math.max(1, Math.floor((area.height - ht) / step) + 1);
            r = {x: area.x + k * step, y: area.y + k * step, width: wd, height: ht};
        } else {
            // Windows 7: in rows (stacked) or columns (side by side), a grid past three
            let cols = n <= 3 ? (mode === "side" ? n : 1) : Math.ceil(Math.sqrt(n));
            let rows = Math.ceil(n / cols);
            if (n > 3 && mode === "stack") { const t = cols; cols = rows; rows = t; }
            const c = i % cols, row = Math.floor(i / cols);
            const wd = Math.floor(area.width / cols), ht = Math.floor(area.height / rows);
            r = {x: area.x + c * wd, y: area.y + row * ht, width: wd, height: ht};
        }
        w.frameGeometry = r;
    });
}
EOF
q=$(command -v qdbus6 || command -v qdbus)
name="kali-looks-arrange-$$"
id=$("$q" org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$f" "$name") || exit 1
"$q" org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script.run >/dev/null 2>&1 \
  || "$q" org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null
sleep 0.5
"$q" org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "$name" >/dev/null
