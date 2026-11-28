#!/usr/bin/env python3
"""kali-looks: brings the macOS Tahoe look in line with the real macOS 26 Tahoe.

Runs before every Tahoe session (Plasma isn't running yet) and after setup. Each
step checks first and changes nothing when it's already right.

  tahoe-finish.py <look config tree>
"""
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
HERE = Path(__file__).resolve().parent
PLASMOIDS = HOME / ".local/share/plasma/plasmoids"
MARK = "kali-looks"


def log(msg):
    print(f"tahoe-finish: {msg}")


# --- small KDE config (INI) editor that keeps everything it doesn't touch ----------------
class KConfig:
    def __init__(self, path):
        self.path = Path(path)
        self.groups = []  # [header, [lines]]
        cur = ["", []]
        for line in self.path.read_text(encoding="utf-8").splitlines():
            if line.startswith("[") and line.rstrip().endswith("]"):
                self.groups.append(cur)
                cur = [line.rstrip(), []]
            else:
                cur[1].append(line)
        self.groups.append(cur)
        self.changed = False

    def save(self):
        if not self.changed:
            return False
        out = []
        for header, lines in self.groups:
            if header:
                out.append(header)
            while lines and lines[-1] == "":
                lines = lines[:-1]
            out.extend(lines)
            if header:
                out.append("")
        self.path.write_text("\n".join(out).rstrip("\n") + "\n", encoding="utf-8")
        return True

    @staticmethod
    def header(*names):
        return "".join(f"[{n}]" for n in names)

    def find(self, *names):
        h = self.header(*names)
        for g in self.groups:
            if g[0] == h:
                return g
        return None

    def get(self, names, key, default=None):
        g = self.find(*names)
        if g:
            for line in g[1]:
                if line.startswith(key + "="):
                    return line[len(key) + 1:]
        return default

    def set(self, names, key, value):
        g = self.find(*names)
        if g is None:
            g = [self.header(*names), []]
            self.groups.append(g)
        for i, line in enumerate(g[1]):
            if line.startswith(key + "="):
                if line != f"{key}={value}":
                    g[1][i] = f"{key}={value}"
                    self.changed = True
                return
        g[1].append(f"{key}={value}")
        self.changed = True

    def remove_tree(self, *names):
        prefix = self.header(*names)
        keep = [g for g in self.groups if not (g[0] == prefix or g[0].startswith(prefix + "["))]
        if len(keep) != len(self.groups):
            self.groups = keep
            self.changed = True

    def children(self, *names):
        """ids of [names][N] groups, direct children only"""
        pat = re.compile(re.escape(self.header(*names)) + r"\[(\d+)\]$")
        return [int(m.group(1)) for g in self.groups if (m := pat.match(g[0]))]

    def max_id(self):
        ids = [0]
        for g in self.groups:
            ids += [int(x) for x in re.findall(r"\[(?:Containments|Applets)\]\[(\d+)\]", g[0])]
        return max(ids)


# --- the menu bar ------------------------------------------------------------------------
TAHOE = "org.kde.mac-tahoe-liquid-kde."
GLOBALMENU = "org.kde.mac.tahoe.liquid.globalmenu"
TRAY = "org.kde.plasma.systemtray"
SPOTLIGHT = "org.kalilooks.tahoe.spotlight"
# Not in a real Tahoe menu bar: the Acrylic Glass settings button and Bluetooth
# (it's in Control Center; macOS shows it in the bar only if you turn that on).
DROP = {TAHOE + "acrylicglass", TAHOE + "bluetooth"}
# Right side, as on a Mac: app icons, then Battery, Wi-Fi, Spotlight, Control Center
# (the clock follows). The notification banners' widget has no icon of its own here.
STATUS_ORDER = [TRAY, TAHOE + "notifications", TAHOE + "battery", TAHOE + "wifi",
                SPOTLIGHT, TAHOE + "controlcenter"]


def tray_widgets():
    ids = []
    for root in (Path("/usr/share/plasma/plasmoids"), PLASMOIDS):
        for meta in sorted(root.glob("*/metadata.json")):
            try:
                m = json.loads(meta.read_text())
            except (OSError, ValueError):
                continue
            if m.get("X-Plasma-NotificationArea") in ("true", True) or m.get("X-Plasma-NotificationAreaCategory"):
                ids.append(m.get("KPlugin", {}).get("Id") or meta.parent.name)
    # KDE's own tray widgets are built into plugins, metadata included
    for so in sorted(Path("/usr/lib/x86_64-linux-gnu/qt6/plugins/plasma/applets").glob("*.so")):
        try:
            if b"X-Plasma-NotificationArea" in so.read_bytes():
                ids.append(so.stem)
        except OSError:
            pass
    return list(dict.fromkeys(ids))


def menu_bars(cfg):
    bars = []
    for cid in cfg.children("Containments"):
        if cfg.get(["Containments", str(cid)], "plugin") != "org.kde.panel":
            continue
        plugins = {cfg.get(["Containments", str(cid), "Applets", str(a)], "plugin")
                   for a in cfg.children("Containments", str(cid), "Applets")}
        if GLOBALMENU in plugins:
            bars.append(cid)
    return bars


def fix_menu_bar(cfg, cid):
    c = ["Containments", str(cid)]
    applets = {a: cfg.get(c + ["Applets", str(a)], "plugin") for a in cfg.children(*c, "Applets")}
    order = [int(x) for x in (cfg.get(c + ["General"], "AppletOrder", "") or "").split(";") if x]
    order = [a for a in order if a in applets] + [a for a in applets if a not in order]

    for a, plugin in list(applets.items()):
        if plugin in DROP:
            cfg.remove_tree(*c, "Applets", str(a))
            del applets[a]
            order.remove(a)
            log(f"menu bar {cid}: removed {plugin.rsplit('.', 1)[-1]}")
    if SPOTLIGHT not in applets.values():
        new = cfg.max_id() + 1
        cfg.set(c + ["Applets", str(new)], "immutability", "1")
        cfg.set(c + ["Applets", str(new)], "plugin", SPOTLIGHT)
        applets[new] = SPOTLIGHT
        order.append(new)
        log(f"menu bar {cid}: added Spotlight")

    # status items in macOS order, where the first of them sits now
    status = [a for p in STATUS_ORDER for a, q in applets.items() if q == p]
    if status:
        at = min(order.index(a) for a in status)
        rest = [a for a in order if a not in status]
        order = rest[:at] + status + rest[at:]
    cfg.set(c + ["General"], "AppletOrder", ";".join(map(str, order)))

    # A Mac's menu bar has no "Search" menu of its own (menu search lives in Help)
    for a, plugin in applets.items():
        if plugin == GLOBALMENU:
            cfg.set(c + ["Applets", str(a), "Configuration", "Appearance"], "enableMenuSearch", "false")

    # The tray holds app icons only (Steam, Discord, ...), all shown, no arrow:
    # no KDE or Windows 7 status widgets next to Tahoe's own Battery and Wi-Fi.
    for a, plugin in applets.items():
        if plugin != TRAY:
            continue
        t = c + ["Applets", str(a)]
        for sub in cfg.children(*t, "Applets"):
            cfg.remove_tree(*t, "Applets", str(sub))
        cfg.set(t + ["General"], "extraItems", "")
        # every tray widget counts as already seen, or Plasma adds its default ones back
        known = [k for k in (cfg.get(t + ["General"], "knownItems", "") or "").split(",") if k]
        cfg.set(t + ["General"], "knownItems", ",".join(known + [k for k in tray_widgets() if k not in known]))
        cfg.set(t + ["General"], "shownItems", "")
        cfg.set(t + ["General"], "showAllItems", "true")
        # App icons (Steam, Discord, ...) are never tucked away behind an arrow, as on a
        # Mac. Only widgets stay on the hidden list (the Tahoe Shell hides KDE's copies
        # of its own Wi-Fi and Battery there).
        widgets = set(tray_widgets())
        hidden = [h for h in (cfg.get(t + ["General"], "hiddenItems", "") or "").split(",") if h]
        cfg.set(t + ["General"], "hiddenItems", ",".join(h for h in hidden if h in widgets or h.startswith("org.kde.")))


def screen_count():
    """Screens X knows about right now (the session hook runs once X is up)."""
    try:
        out = subprocess.run(["xrandr", "--listmonitors"], capture_output=True, text=True, timeout=10).stdout
        m = re.match(r"Monitors:\s*(\d+)", out)
        return int(m.group(1)) if m else 0
    except (OSError, subprocess.SubprocessError):
        return 0


def menu_bar_every_screen(cfg, tree, screens):
    """A Mac has the menu bar on every screen (the Dock stays on the main one). Each
    extra bar is an exact copy of the main one, made before Plasma starts, so the
    Tahoe Shell's MenuBarSync finds them alike."""
    bars = menu_bars(cfg)
    if not bars or screens < 2:
        return
    on = {}
    for cid in bars:
        try:
            on.setdefault(int(cfg.get(["Containments", str(cid)], "lastScreen", "-1")), cid)
        except ValueError:
            pass
    main = on.get(0, min(bars))
    src = f"[Containments][{main}]"
    groups = [g for g in cfg.groups if g[0] == src or g[0].startswith(src + "[")]
    applet_ids = sorted({int(x) for g in groups for x in re.findall(r"\[Applets\]\[(\d+)\]", g[0])})
    rc = KConfig(Path(tree) / "plasmashellrc") if (Path(tree) / "plasmashellrc").exists() else None
    for screen in range(screens):
        if screen in on:
            continue
        nid = cfg.max_id() + 1
        ids = {main: nid}
        for a in applet_ids:
            ids[a] = nid + 1 + len(ids) - 1
        def remap_header(h):
            h = h.replace(src, f"[Containments][{nid}]", 1)
            return re.sub(r"\[Applets\]\[(\d+)\]", lambda m: f"[Applets][{ids.get(int(m.group(1)), int(m.group(1)))}]", h)
        def remap_line(line):
            if line.startswith("AppletOrder="):
                return "AppletOrder=" + ";".join(str(ids.get(int(x), x)) for x in line[12:].split(";") if x)
            if line.startswith("lastScreen=") and not line.startswith("lastScreen=-"):
                return f"lastScreen={screen}"
            if line.startswith("panelWidgets="):
                return re.sub(r'"id":(\d+)', lambda m: f'"id":{ids.get(int(m.group(1)), int(m.group(1)))}', line)
            return line
        for h, lines in groups:
            cfg.groups.append([remap_header(h), [remap_line(l) for l in lines]])
        cfg.changed = True
        on[screen] = nid
        if rc is not None and rc.find("PlasmaViews", f"Panel {main}"):
            for line in rc.find("PlasmaViews", f"Panel {main}")[1]:
                if "=" in line:
                    k, v = line.split("=", 1)
                    rc.set(["PlasmaViews", f"Panel {nid}"], k, v)
        log(f"menu bar copied to screen {screen + 1}")
    if rc is not None:
        rc.save()


def menu_bar(tree):
    path = Path(tree) / "plasma-org.kde.plasma.desktop-appletsrc"
    if not path.exists():
        return
    cfg = KConfig(path)
    for cid in menu_bars(cfg):
        fix_menu_bar(cfg, cid)
    menu_bar_every_screen(cfg, tree, screen_count())
    if cfg.save():
        log("menu bar items set to Battery, Wi-Fi, Spotlight, Control Center, clock")


# --- our own widgets, and the notification widget without its bell ---------------------
def install_plasmoids():
    for src in sorted((HERE / "plasmoids").iterdir()):
        dst = PLASMOIDS / src.name
        same = dst.exists() and all(
            (dst / f.relative_to(src)).exists() and (dst / f.relative_to(src)).read_bytes() == f.read_bytes()
            for f in src.rglob("*") if f.is_file())
        if not same:
            shutil.rmtree(dst, ignore_errors=True)
            shutil.copytree(src, dst)
            log(f"installed {src.name}")


def no_bell():
    """The notification widget shows the banners, but a Mac has no bell icon in the menu
    bar: its button takes no space (banners and Control Center's list still work)."""
    qml = PLASMOIDS / (TAHOE + "notifications") / "contents/ui/main.qml"
    if not qml.exists():
        return
    s = qml.read_text()
    if f"{MARK}: no bell" in s:
        return
    anchor = "    fullRepresentation: Controls.PanelButton {\n"
    if anchor not in s:
        log("notifications: layout changed upstream, bell left as is")
        return
    s = s.replace(anchor, anchor + f"        // {MARK}: no bell in the menu bar, as on a Mac\n"
                  "        visible: false; implicitWidth: 0; Layout.minimumWidth: 0; Layout.maximumWidth: 0\n", 1)
    if "import QtQuick.Layouts" not in s:
        s = s.replace("import QtQuick\n", "import QtQuick\nimport QtQuick.Layouts\n", 1)
    qml.write_text(s)
    log("notifications: bell hidden")


# --- wallpaper: the theme names Tahoe's picture with the wrong file type ----------------
def wallpaper_defaults():
    """MacTahoe's Plasma theme says its default wallpaper is a .jpeg, but the picture is a
    .jpg, so Plasma fell back to its own blue "Next". New desktops (a screen plugged in)
    start from these defaults."""
    for theme in (HOME / ".local/share/plasma/desktoptheme").glob("MacTahoeLiquidKde-*/plasmarc"):
        s = theme.read_text()
        n = re.sub(r"(?m)^defaultFileSuffix=\.jpeg$", "defaultFileSuffix=.jpg", s)
        if n != s:
            theme.write_text(n)
            log(f"{theme.parent.name}: default wallpaper found again (.jpg)")
    for lnf in (HOME / ".local/share/plasma/look-and-feel").glob("org.kde.mac-tahoe-liquid-kde.*/contents/defaults"):
        s = lnf.read_text()
        if re.search(r"(?m)^\[Wallpaper\]$", s):
            continue
        lnf.write_text(s.rstrip("\n") + "\n\n[Wallpaper]\nImage=MacTahoe\n")
        log(f"{lnf.parent.parent.name}: new desktops start with the Tahoe wallpaper")


# --- app colors: the Tahoe widget style is Kvantum, and needs its theme here -----------
KVANTUM_SRC = HOME / ".local/share/kali-looks/src/macos-tahoe/src/offline/kvantum/mac-tahoe-liquid-kde"


def kvantum(tree):
    """The "MacTahoe" Qt style is the Kvantum engine with Tahoe's theme. The upstream
    installer copies that theme to the real ~/.config, which was another session's
    settings folder, so in this look Kvantum found no theme and drew every app with its
    built-in dark grey (and told the desktop portal "dark mode", so the rest followed)."""
    if not KVANTUM_SRC.is_dir():
        return
    kv = Path(tree) / "Kvantum"
    for name in ("mac-tahoe-liquid-kde", "mac-tahoe-liquid-kdeDark"):
        dst = kv / name
        for ext in (".kvconfig", ".svg"):
            src = KVANTUM_SRC / (name + ext)
            if not src.exists():
                continue
            target = dst / (name + ext)
            if not target.exists() or target.read_bytes() != src.read_bytes():
                dst.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(src, target)
                log(f"Kvantum: {name}{ext} in place")
    chooser = kv / "kvantum.kvconfig"
    text = chooser.read_text() if chooser.exists() else ""
    if re.search(r"(?m)^theme=mac-tahoe-liquid-kde(Dark)?$", text):
        return
    kdeglobals = Path(tree) / "kdeglobals"
    scheme = re.search(r"(?m)^ColorScheme=(.*)$", kdeglobals.read_text()) if kdeglobals.exists() else None
    theme = "mac-tahoe-liquid-kdeDark" if scheme and scheme.group(1).strip().endswith("Dark") else "mac-tahoe-liquid-kde"
    cfg = KConfig(chooser) if chooser.exists() else None
    if cfg is None:
        chooser.write_text(f"[General]\ntheme={theme}\n")
    else:
        cfg.set(["General"], "theme", theme)
        cfg.save()
    log(f"Kvantum: apps drawn with {theme}")


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    tree = sys.argv[1]
    install_plasmoids()
    kvantum(tree)
    no_bell()
    wallpaper_defaults()
    menu_bar(tree)


if __name__ == "__main__":
    main()
