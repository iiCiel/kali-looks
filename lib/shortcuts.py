#!/usr/bin/env python3
"""kali-looks: the keyboard shortcuts every look needs, filled in where they're missing.

A look's first setup runs in a hidden session, and KDE came out of it with nearly
every global shortcut switched off ("none"): the volume, mute, media and brightness
keys, Alt+Tab, Show Desktop, tiling, and the rest, and no screenshot keys at all
(Spectacle never registered). Two passes, before the session starts while nothing
holds the file:

- once per look (and again after each `looks setup`, which deletes the stamp): every
  shortcut KDE shows as switched off goes back to KDE's own default, unless another
  action already uses that key or the look leaves it off on purpose (a Mac has no
  Meta-tap menu, and Cmd+Q quits apps there);
- every login: closing, force quitting, screenshots and the task manager in each
  look's own style, only where missing or off, so a shortcut you set yourself stays.

  shortcuts.py <look's config folder> <look>
Safe to run again.
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
# KDE defaults a look leaves off on purpose: (group, action)
LEFT_OFF = {
    "macos": {("[plasmashell]", "activate application launcher"),  # Meta alone opens nothing on a Mac
              ("[plasmashell]", "manage activities")},  # Meta+Q: Cmd+Q is Quit on a Mac
    "windows": set(),
}
STAMP = ".kali-looks-shortcut-defaults"  # in the look's config folder: defaults put back


TAB = r"\t"  # KDE separates several keys for one action with a literal \t


def keys_of(value):
    """The key sequences in a stored value."""
    return [k for k in value.split(TAB) if k and k != "none"]


def restore_defaults(groups, style):
    """Every action stored as none,<default>,<name> gets its default back. A key another
    action already uses is left out (the first one keeps it). Returns the actions set."""
    used, offs = set(), []
    for name, body in groups:
        for i, line in enumerate(body):
            if "=" not in line or line.startswith("_k_friendly_name"):
                continue
            key, value = line.rstrip("\n").split("=", 1)
            if name.startswith("[services]"):
                used.update(keys_of(value))
                continue
            parts = value.split(",", 2)
            if len(parts) != 3:
                continue
            if parts[0] == "none" and keys_of(parts[1]) and (name, key) not in LEFT_OFF[style]:
                offs.append((name, body, i, key, parts))
            else:
                used.update(keys_of(parts[0]))
    done = []
    for name, body, i, key, (_, default, label) in offs:
        free = [k for k in keys_of(default) if k not in used]
        if not free:
            continue
        used.update(free)
        body[i] = f"{key}={TAB.join(free)},{default},{label}\n"
        done.append(f"{name.strip('[]')} {key}")
    return done


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
    stamp = cfg / STAMP
    if rc.exists() and not stamp.exists():
        back = restore_defaults(groups, style)
        if back:
            print(f"shortcuts: {len(back)} KDE defaults back on (" + ", ".join(back[:6])
                  + (", ..." if len(back) > 6 else "") + ")")
    for action, (keys, label) in KWIN.items():
        if set_missing(groups, "[kwin]", action, f"{keys},{keys},{label}",
                       lambda v: v.split(",", 1)[0] == "none"):
            changed.append(action)
    for group, keys in STYLES[style].items():
        for key, value in keys.items():
            if set_missing(groups, group, key, value, lambda v: v in ("", "none")):
                changed.append(f"{group.split('][')[-1].rstrip(']')} {key}")
    if changed or (rc.exists() and not stamp.exists()):
        text = "".join((name + "\n" if name else "") + "".join(body) for name, body in groups)
        rc.write_text(text)
    if changed:
        print("shortcuts: set " + ", ".join(changed))
    if rc.exists():
        stamp.touch()


if __name__ == "__main__":
    main()
