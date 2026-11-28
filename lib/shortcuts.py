#!/usr/bin/env python3
"""kali-looks: the keyboard shortcuts every look needs, filled in where they're missing.

Each look starts its KDE settings fresh, and in them KDE came up with no screenshot
keys at all (Spectacle never registered) and with Close Window (Alt+F4) and Kill
Window switched off. This puts back closing, force quitting, screenshots and the task
manager, in each look's own style. Only keys that are missing or switched off ("none")
are written: a shortcut you set yourself is left alone. Runs before the session
starts, while nothing holds the file. Safe to run again.

  shortcuts.py <look's config folder> <look>
"""
import sys
from pathlib import Path

KWIN = {  # kwin actions: current,default,name
    "Window Close": ("Alt+F4", "Close Window"),
    "Kill Window": ("Meta+Ctrl+Esc", "Kill Window"),
}
SPECTACLE = "[services][org.kde.spectacle.desktop]"
MONITOR = "[services][org.kde.plasma-systemmonitor.desktop]"
# KDE writes several keys for one action with a tab, stored as \t
STYLES = {
    # Mac: Cmd+Shift+3 whole screen, +4 an area, +5 the screenshot tool; Ctrl+Esc for
    # Activity Monitor (Meta+Shift+digit arrives as Meta+symbol in KDE)
    "macos": {SPECTACLE: {"_launch": r"Print\tMeta+%", "FullScreenScreenShot": r"Shift+Print\tMeta+#",
                          "RectangularRegionScreenShot": r"Meta+Shift+Print\tMeta+$",
                          "ActiveWindowScreenShot": "Meta+Print"},
              MONITOR: {"_launch": "Ctrl+Esc"}},
    # Windows: Print Screen, Win+Shift+S for the snipping tool, Ctrl+Shift+Esc for Task Manager
    "windows": {SPECTACLE: {"_launch": r"Print\tMeta+Shift+S", "FullScreenScreenShot": "Shift+Print",
                            "RectangularRegionScreenShot": "Meta+Shift+Print",
                            "ActiveWindowScreenShot": "Meta+Print"},
                MONITOR: {"_launch": "Ctrl+Shift+Esc"}},
}
STYLE_OF = {"macos": "macos", "win7": "windows", "winxp": "windows"}


def parse(lines):
    """[(group, [lines])] in file order; group '' holds anything before the first."""
    groups, name, body = [], "", []
    for line in lines:
        if line.startswith("[") and line.rstrip().endswith("]"):
            groups.append((name, body))
            name, body = line.rstrip(), []
        else:
            body.append(line)
    groups.append((name, body))
    return groups


def key_index(body, key):
    for i, line in enumerate(body):
        if line.split("=", 1)[0] == key:
            return i
    return -1


def set_missing(groups, group, key, value, disabled):
    """Write key=value if the key is missing or disabled(current value). True if changed."""
    for name, body in groups:
        if name == group:
            i = key_index(body, key)
            if i >= 0:
                if not disabled(body[i].split("=", 1)[1].rstrip("\n")):
                    return False
                body[i] = f"{key}={value}\n"
                return True
            at = len(body)
            while at and body[at - 1].strip() == "":
                at -= 1
            body.insert(at, f"{key}={value}\n")
            return True
    if groups[-1][1] and groups[-1][1][-1].strip():
        groups[-1][1].append("\n")
    groups.append((group, [f"{key}={value}\n", "\n"]))
    return True


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    cfg, look = Path(sys.argv[1]), sys.argv[2]
    style = STYLE_OF.get(look)
    if style is None:
        return
    rc = cfg / "kglobalshortcutsrc"
    groups = parse(rc.read_text().splitlines(keepends=True) if rc.exists() else [])
    changed = []
    for action, (keys, label) in KWIN.items():
        if set_missing(groups, "[kwin]", action, f"{keys},{keys},{label}",
                       lambda v: v.split(",", 1)[0] == "none"):
            changed.append(action)
    for group, keys in STYLES[style].items():
        for key, value in keys.items():
            if set_missing(groups, group, key, value, lambda v: v in ("", "none")):
                changed.append(f"{group.split('][')[-1].rstrip(']')} {key}")
    if changed:
        text = "".join((name + "\n" if name else "") + "".join(body) for name, body in groups)
        rc.write_text(text)
        print("shortcuts: set " + ", ".join(changed))


if __name__ == "__main__":
    main()
