#!/usr/bin/env python3
"""kali-looks: the Dock under the pointer, as on a Mac.

On a Mac (magnification off, the default) pointing at a Dock icon only shows the
app's name above it. The Tahoe Shell also draws the icon in KDE's "active" state,
which washes it out, and gives open apps KDE's tooltip (window title and a close
button). This keeps the icons unchanged and shows just the name, open or not (the
size stays as set by dockMagnification, which tahoe-finish sets to 100). Patches the
task manager's source before it's built; safe to run again.

  patch-dock-hover.py <macos-tahoe source tree>
"""
import sys
from pathlib import Path

UI = "src/offline/plasmoids/org.kde.mac.tahoe.liquid.taskmanager/contents/ui/"

EDITS = [
    ("kali-looks: no hover wash", UI + "Task.qml",
     "            anchors.fill: parent\n\n            active: task.highlighted\n            enabled: true\n",
     "            anchors.fill: parent\n\n            // kali-looks: no hover wash: a Mac shows the name, the icon itself doesn't change\n"
     "            active: false\n            enabled: true\n"),
    ("kali-looks: name only", UI + "ToolTipDelegate.qml",
     "    sourceComponent: isLauncher && parentTask?.tasksRoot.iconsOnly && !playerData\n"
     "        ? dockLauncherLabel : isGroup ? groupToolTip : singleTooltip\n",
     "    // kali-looks: name only, open or not, as on a Mac\n"
     "    sourceComponent: parentTask?.tasksRoot.iconsOnly && !playerData\n"
     "        ? dockLauncherLabel : isGroup ? groupToolTip : singleTooltip\n"),
]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    src = Path(sys.argv[1])
    results = []
    for mark, rel, old, new in EDITS:
        f = src / rel
        s = f.read_text()
        if mark in s:
            results.append("already")
        elif old in s:
            f.write_text(s.replace(old, new, 1))
            results.append("patched")
        else:
            sys.exit(f"dock hover: {Path(rel).name} changed upstream; not patched")
    print("dock hover: icon " + results[0] + ", name " + results[1])


if __name__ == "__main__":
    main()
