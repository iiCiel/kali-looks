"""kali-looks: the XP session's taskbars, put right in Plasma's own files before the
session starts (Plasma isn't running then, so nothing writes them back).

- one taskbar per screen: extra ones (made twice at a login that raced Plasma's
  start) go;
- every taskbar has the notification area (volume, network, battery...) and the clock,
  and lists every window, so they all show the same, as one XP taskbar would;
- the notification area holds KDE's own items, themed by XPlasma, not Windows 7's
  (AeroShell's io.gitgud.wackyideas.*, installed for the Windows 7 look);
- volume, network and battery are always in sight, the battery with its percentage.
"""
import re
from pathlib import Path

APPLETS = "plasma-org.kde.plasma.desktop-appletsrc"
FOREIGN = "io.gitgud.wackyideas."
ALWAYS_SHOWN = ["org.kde.plasma.volume", "org.kde.plasma.networkmanagement", "org.kde.plasma.battery"]


class Ini:
    """KDE config file, kept in order: [(group, [lines])]; group None is the head."""

    def __init__(self, text):
        self.groups = [[None, []]]
        for line in text.splitlines():
            if line.startswith("[") and line.rstrip().endswith("]"):
                self.groups.append([line.rstrip()[1:-1], []])
            else:
                self.groups[-1][1].append(line)

    def text(self):
        out = []
        for name, lines in self.groups:
            if name is not None:
                out.append(f"[{name}]")
            out.extend(lines)
        return "\n".join(out).rstrip("\n") + "\n"

    def names(self):
        return [g[0] for g in self.groups if g[0] is not None]

    def lines(self, name):
        for g in self.groups:
            if g[0] == name:
                return g[1]
        return None

    def get(self, name, key, default=None):
        for line in self.lines(name) or []:
            if line.startswith(key + "="):
                return line[len(key) + 1:]
        return default

    def set(self, name, key, value):
        lines = self.lines(name)
        if lines is None:
            self.groups.append([name, [f"{key}={value}", ""]])
            return
        for i, line in enumerate(lines):
            if line.startswith(key + "="):
                lines[i] = f"{key}={value}"
                return
        at = len(lines)
        while at > 0 and lines[at - 1] == "":
            at -= 1
        lines.insert(at, f"{key}={value}")

    def drop(self, prefix):
        """Remove a group and every group under it."""
        self.groups = [g for g in self.groups
                       if g[0] is None or not (g[0] == prefix or g[0].startswith(prefix + "]["))]


def ids(name):
    return name.split("][")


def fix(cfg):
    """Returns what was changed (empty: nothing to do)."""
    path = Path(cfg) / APPLETS
    if not path.exists():
        return []
    ini = Ini(path.read_text())
    done = []
    names = ini.names()
    containments = {}
    for n in names:
        p = ids(n)
        if len(p) == 2 and p[0] == "Containments":
            containments[p[1]] = n
    applets = {}  # containment id -> {applet id: plugin}
    for n in names:
        p = ids(n)
        if len(p) == 4 and p[0] == "Containments" and p[2] == "Applets":
            applets.setdefault(p[1], {})[p[3]] = ini.get(n, "plugin", "")
    panels = [c for c, n in containments.items()
              if ini.get(n, "plugin") == "org.kde.panel" and ini.get(n, "location") == "4"]
    if not panels:
        return []

    def has(c, plugin):
        return plugin in applets.get(c, {}).values()

    def applet_of(c, plugin):
        for a, p in applets.get(c, {}).items():
            if p == plugin:
                return a
        return None

    main = min((c for c in panels if has(c, "org.kde.plasma.systemtray") and has(c, "fyi.hotsocket.xplasma.start")),
               key=int, default=None)
    if main is None:
        return []

    # One taskbar per screen.
    by_screen = {}
    for c in panels:
        by_screen.setdefault(ini.get(containments[c], "lastScreen", "-1"), []).append(c)
    shell = Path(cfg) / "plasmashellrc"
    shellini = Ini(shell.read_text()) if shell.exists() else None
    for screen, cs in by_screen.items():
        keep = main if main in cs else min(cs, key=lambda c: (not has(c, "org.kde.plasma.systemtray"), int(c)))
        for c in cs:
            if c == keep:
                continue
            ini.drop(f"Containments][{c}")
            if shellini:
                shellini.drop(f"PlasmaViews][Panel {c}")
            panels.remove(c)
            done.append(f"extra taskbar {c} on screen {screen} removed")

    # Ids in use, to give cloned applets new ones.
    used = set()
    for n in ini.names():
        for a, b in zip(ids(n), ids(n)[1:]):
            if a in ("Containments", "Applets") and b.isdigit():
                used.add(int(b))
    next_id = [max(used, default=0) + 1]

    def new_id():
        i = next_id[0]
        next_id[0] += 1
        return str(i)

    tray = applet_of(main, "org.kde.plasma.systemtray")
    tray_prefix = f"Containments][{main}][Applets][{tray}"

    # Every taskbar gets the notification area: a copy of the main one's.
    for c in panels:
        if c == main or has(c, "org.kde.plasma.systemtray"):
            continue
        new = new_id()
        renames = {}
        copies = []
        for name, lines in ini.groups:
            if name is None or not (name == tray_prefix or name.startswith(tray_prefix + "][")):
                continue
            rest = name[len(tray_prefix):]
            m = re.match(r"^\]\[Applets\]\[(\d+)(?=\]|$)", rest)
            if m and m.group(1) not in renames:
                renames[m.group(1)] = new_id()
            if m:
                rest = f"][Applets][{renames[m.group(1)]}" + rest[m.end():]
            copies.append([f"Containments][{c}][Applets][{new}" + rest, list(lines)])
        # after the panel's last group
        last = max(i for i, g in enumerate(ini.groups) if g[0] and (g[0] == f"Containments][{c}" or g[0].startswith(f"Containments][{c}][")))
        ini.groups[last + 1:last + 1] = copies
        order = ini.get(f"Containments][{c}][General", "AppletOrder", "")
        items = [i for i in order.split(";") if i]
        clock = applet_of(c, "fyi.hotsocket.xplasma.clock")
        if clock in items:
            items.insert(items.index(clock), new)
        else:
            items.append(new)
        ini.set(f"Containments][{c}][General", "AppletOrder", ";".join(items))
        applets.setdefault(c, {})[new] = "org.kde.plasma.systemtray"
        done.append(f"notification area added to taskbar {c}")

    # Every taskbar lists every window.
    for c in panels:
        for a, plugin in applets.get(c, {}).items():
            if plugin == "org.kde.plasma.taskmanager":
                g = f"Containments][{c}][Applets][{a}][Configuration][General"
                if ini.get(g, "showOnlyCurrentScreen") != "false":
                    ini.set(g, "showOnlyCurrentScreen", "false")
                    done.append(f"taskbar {c} lists every window")

    # Notification areas: KDE's items only; battery with its percentage.
    for name in list(ini.names()):
        p = ids(name)
        if not (len(p) == 4 and p[0] == "Containments" and p[2] == "Applets"):
            continue
        if ini.get(name, "plugin") != "org.kde.plasma.systemtray":
            continue
        g = name + "][General"
        extra = ini.get(g, "extraItems")
        if extra is not None:
            kept = [i for i in extra.split(",") if i and not i.startswith(FOREIGN)]
            if kept != extra.split(","):
                ini.set(g, "extraItems", ",".join(kept))
                done.append(f"Windows 7 items out of {p[3]}'s notification area")
        # Volume, network and the battery always in sight (as XP's laptops had its power
        # meter); Plasma otherwise tucks the battery away once it's full and charging.
        shown = [i for i in (ini.get(g, "shownItems") or "").split(",") if i]
        want = shown + [i for i in ALWAYS_SHOWN if i not in shown]
        if want != shown:
            ini.set(g, "shownItems", ",".join(want))
            done.append(f"volume, network and battery always shown in {p[3]}'s notification area")
        for sub in list(ini.names()):
            q = ids(sub)
            if len(q) == 6 and sub.startswith(name + "][Applets]["):
                plugin = ini.get(sub, "plugin", "")
                if plugin.startswith(FOREIGN):
                    ini.drop(sub)
                elif plugin == "org.kde.plasma.battery":
                    bg = sub + "][Configuration][General"
                    if ini.get(bg, "showPercentage") != "true":
                        ini.set(bg, "showPercentage", "true")
                        done.append("battery percentage shown")

    if done:
        path.write_text(ini.text())
        if shellini:
            shell.write_text(shellini.text())
    return done
