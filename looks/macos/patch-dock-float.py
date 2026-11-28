#!/usr/bin/env python3
"""kali-looks: the Dock keeps floating above the screen edge, so its running dots show.

On a Tahoe Mac the Dock floats a little above the bottom edge, with a dot under each
running app, even when a window is zoomed to fill the screen. The Tahoe Shell's
"dock flush" effect lowers the Dock onto the edge whenever a maximized window shares
its screen, which pushes the dots (drawn at the bottom of the Dock) off the screen.
This keeps the Dock where it floats (the lowering becomes 0 px) and has maximized
windows stop at the Dock's top as before. Patches the effect and the Dock script in
the source tree and, when given, the installed copies; safe to run again.

  patch-dock-float.py <macos-tahoe source tree> [kwin data dir, e.g. ~/.local/share/kwin]
"""
import sys
from pathlib import Path

MARK = "kali-looks: the Dock keeps floating"
EDITS = {
    "effect": ("kwin-effects/dock-flush/contents/code/main.js", "effects/mttkde_dock_flush/contents/code/main.js",
               "const GAP = 10;",
               "const GAP = 0;   // " + MARK + " (was 10: the edge hid the running dots)\n//"),
    "script": ("kwin-scripts/mttkde-dock-follows-screen/contents/code/main.js",
               "scripts/mttkde-dock-follows-screen/contents/code/main.js",
               "const FLUSH_GAP = 10;",
               "const FLUSH_GAP = 0;   // " + MARK + " (was 10)\n//"),
}


def patch(path, old, new):
    if not path.exists():
        return f"{path}: not found"
    s = path.read_text()
    if MARK in s:
        return f"{path.name}: already patched"
    if old not in s:
        sys.exit(f"dock float: {path} changed upstream; not patched")
    path.write_text(s.replace(old, new, 1))
    return f"{path.parent.parent.parent.name}: patched"


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    src = Path(sys.argv[1]) / "src/offline"
    installed = Path(sys.argv[2]).expanduser() if len(sys.argv) == 3 else None
    for rel_src, rel_inst, old, new in EDITS.values():
        print("dock float:", patch(src / rel_src, old, new))
        if installed:
            print("dock float:", patch(installed / rel_inst, old, new))


if __name__ == "__main__":
    main()
