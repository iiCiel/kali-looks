#!/usr/bin/env python3
"""kali-looks: brings the macOS Tahoe look in line with the real macOS 26 Tahoe.

Runs before every Tahoe session (Plasma isn't running yet) and after setup. Each
step checks first and changes nothing when it's already right.

  tahoe-finish.py <look config tree>
  tahoe-finish.py --live      once the session is up (after-start)
  tahoe-finish.py --screens   when screens change (kali-looks-tahoe-screens.path)
  tahoe-finish.py --wallpaper when a wallpaper changes (kali-looks-tahoe-wallpaper.path)
"""
import json
import os
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


def menu_bar_views(cfg, tree):
    """Bars added while the session ran (screens.js) can't set how Plasma draws them:
    give each the main bar's look (glass behind the items, no panel background)."""
    path = Path(tree) / "plasmashellrc"
    bars = menu_bars(cfg)
    if not path.exists() or len(bars) < 2:
        return
    rc = KConfig(path)
    on = {}
    for cid in bars:
        try:
            on.setdefault(int(cfg.get(["Containments", str(cid)], "lastScreen", "-1")), cid)
        except ValueError:
            pass
    main = rc.find("PlasmaViews", f"Panel {on.get(0, min(bars))}")
    if not main:
        return
    for cid in bars:
        for line in main[1]:
            if "=" in line:
                k, v = line.split("=", 1)
                rc.set(["PlasmaViews", f"Panel {cid}"], k, v)
    if rc.save():
        log("menu bars on every screen drawn alike")


def menu_bar(tree):
    path = Path(tree) / "plasma-org.kde.plasma.desktop-appletsrc"
    if not path.exists():
        return
    cfg = KConfig(path)
    for cid in menu_bars(cfg):
        fix_menu_bar(cfg, cid)
    menu_bar_every_screen(cfg, tree, screen_count())
    menu_bar_views(cfg, tree)
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
            if not target.exists():
                dst.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(src, target)
                log(f"Kvantum: {name}{ext} in place")
        solid_content(dst / (name + ".kvconfig"))
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


# --- the desktop's right-click menu and Spotlight --------------------------------------
def desktop_menu(tree):
    """A Mac's desktop menu has no "Enter Edit Mode" or "Display Configuration" (KDE's);
    New Folder, sorting and Change Wallpaper have their KDE counterparts there already."""
    path = Path(tree) / "plasma-org.kde.plasma.desktop-appletsrc"
    if not path.exists():
        return
    cfg = KConfig(path)
    for n in cfg.children("ActionPlugins"):
        if cfg.get(["ActionPlugins", str(n)], "RightButton;NoModifier") != "org.kde.contextmenu":
            continue
        for key in ("desktop edit mode", "edit mode", "_display_settings"):
            cfg.set(["ActionPlugins", str(n), "RightButton;NoModifier"], key, "false")
    if cfg.save():
        log("desktop menu without Enter Edit Mode and Display Configuration")


def spotlight(tree):
    """Spotlight floats in the middle of the screen; KRunner sits on the top edge unless
    it's free-floating."""
    path = Path(tree) / "krunnerrc"
    if not path.exists():
        path.write_text("[General]\nFreeFloating=true\n")
        log("Spotlight (KRunner) floats mid-screen")
        return
    cfg = KConfig(path)
    cfg.set(["General"], "FreeFloating", "true")
    if cfg.save():
        log("Spotlight (KRunner) floats mid-screen")


# --- the Dock, as on a Mac with default settings -----------------------------------------
ICONTASKS = "org.kde.mac.tahoe.liquid.icontasks"


def dock(tree):
    """Magnification off (a Mac's default), only app names on hover, and windows stop
    above the Dock, as Zoom fills the space between the Dock and the menu bar."""
    path = Path(tree) / "plasma-org.kde.plasma.desktop-appletsrc"
    if not path.exists():
        return
    cfg = KConfig(path)
    docks = []
    for cid in cfg.children("Containments"):
        c = ["Containments", str(cid)]
        if cfg.get(c, "plugin") != "org.kde.panel":
            continue
        for a in cfg.children(*c, "Applets"):
            if cfg.get(c + ["Applets", str(a)], "plugin") == ICONTASKS:
                cfg.set(c + ["Applets", str(a), "Configuration", "General"], "dockMagnification", "100")
                # pointing at an open app shows its name, not KDE's window preview
                cfg.set(c + ["Applets", str(a), "Configuration", "General"], "showToolTips", "false")
                docks.append(cid)
    if cfg.save():
        log("Dock: no magnification, names only on hover")
    rcpath = Path(tree) / "plasmashellrc"
    if docks and rcpath.exists():
        rc = KConfig(rcpath)
        for cid in docks:
            rc.set(["PlasmaViews", f"Panel {cid}"], "panelVisibility", "0")
        if rc.save():
            log("Dock: windows stop above it")


DOCK_QML = {
    # plasmoid: [(old, new), ...]; the icon stays as it is under the pointer
    TAHOE + "trashcan": [("active: mouseArea.containsMouse || root.containsAcceptableDrag",
                          "active: root.containsAcceptableDrag /* kali-looks */"),
                         ("hovered: mouseArea.containsMouse", "hovered: false /* kali-looks */"),
                         # the label says "Trash", as on a Mac (no item count)
                         ("            subText: root.toolTipSubText", "            subText: \"\" /* kali-looks */")],
    TAHOE + "downloads": [("active: pointer.containsMouse || popup.visible", "active: false /* kali-looks */"),
                          ("hovered: pointer.containsMouse", "hovered: false /* kali-looks */")],
    TAHOE + "launcher": [("active: mouseArea.containsMouse", "active: false /* kali-looks */"),
                         ("hovered: mouseArea.containsMouse", "hovered: false /* kali-looks */")],
}


def dock_hover():
    """Apps, Downloads and Trash: no wash or growth under the pointer (Trash still
    darkens while you drag something over it, as on a Mac)."""
    for plasmoid, edits in DOCK_QML.items():
        for qml in sorted((PLASMOIDS / plasmoid / "contents/ui").glob("*.qml")):
            s = qml.read_text()
            n = s
            for old, new in edits:
                n = n.replace(old, new)
            if n != s:
                qml.write_text(n)
                log(f"Dock: {plasmoid.rsplit('.', 1)[-1]} icon steady under the pointer")


def dock_dots():
    """The running-app dots are dark in light mode on a Mac; the theme draws them white."""
    import gzip
    svg = HOME / ".local/share/plasma/desktoptheme/MacTahoeLiquidKde-Light/widgets/tasks.svgz"
    if not svg.exists():
        return
    s = gzip.open(svg).read().decode()
    def recolor(m):
        return m.group(0).replace('fill="#ffffff"', 'fill="#1d1d1f"')
    n = re.sub(r'<rect\b[^>]*\bid="rect1153-3(?:-10|-0)?"[^>]*>', recolor, s)
    if n != s:
        with gzip.open(svg, "wb") as f:
            f.write(n.encode())
        for cache in (HOME / ".cache").glob("plasma_theme_MacTahoeLiquidKde-Light*.kcache"):
            cache.unlink(missing_ok=True)
        (HOME / ".cache/ksvg-elements").unlink(missing_ok=True)
        log("Dock: running dots dark, as in light mode on a Mac")


SOLID_KEYS = ("base.color", "inactive.base.color", "alt.base.color", "inactive.alt.base.color")


def solid_content(kvconfig):
    """macOS keeps content areas (file lists, text, tables) solid and puts the glass in
    sidebars and toolbars; the theme made them 55% see-through."""
    if not kvconfig.exists():
        return
    s = kvconfig.read_text()
    n = s
    for key in SOLID_KEYS:
        n = re.sub(rf"(?m)^({re.escape(key)}=#[0-9A-Fa-f]{{6}})[0-9A-Fa-f]{{2}}$", r"\1", n)
    if n != s:
        kvconfig.write_text(n)
        log(f"Kvantum: solid content areas in {kvconfig.stem}")


# --- glass: run the Tahoe Shell's own generator on this look's settings ---------------
GLASS_SCRIPT = HOME / ".local/share/kali-looks/src/macos-tahoe/src/scripts/glass_surface_settings.py"


def glass(tree):
    """The generator makes the Finder profile for Dolphin and the windows' glass (and
    the Dock's) from the materials in kwinrc. It ran before this look had its own
    Kvantum folder, so Finder and the windows never got theirs."""
    kwinrc = Path(tree) / "kwinrc"
    if not GLASS_SCRIPT.exists() or not kwinrc.exists():
        return
    cfg = KConfig(kwinrc)
    raw = cfg.get(["Effect-liquidglass"], "ComponentMaterials", "")
    try:
        materials = json.loads(raw) if raw else None
    except ValueError:
        materials = None
    if not materials or "dock" not in materials:
        return
    finder = Path(tree) / "Kvantum/mac-tahoe-liquid-kdeFinder"
    if finder.is_dir():
        return
    env = dict(os.environ, XDG_CONFIG_HOME=str(tree))
    r = subprocess.run([sys.executable, str(GLASS_SCRIPT), "--apply"], input=json.dumps(materials),
                       capture_output=True, text=True, env=env, timeout=120)
    if r.returncode == 0:
        log("glass: Dock, windows and Finder profile generated")
    else:
        log("glass: generator failed: " + (r.stderr or r.stdout).strip()[:300])


# --- Finder: the file manager's name and sidebar, in this look only --------------------
LANG_VARIANT = "en_KL"   # an English "variant" holding only Finder's names
ENV_SCRIPT = """# kali-looks: Finder's names in the macOS Tahoe look. The en_KL English variant
# (~/.local/share/locale/en_KL) only renames Dolphin to Finder and its sidebar sections;
# everything else stays standard English. This look only; cleared when you switch.
case "${LANG:-en}" in
  en*|C|C.*|POSIX) case ":${LANGUAGE:-}:" in *:en_KL:*) ;; *) export LANGUAGE="en_KL:${LANGUAGE:-en_US}" ;; esac ;;
esac
"""


def finder_names(tree):
    """Dolphin is Finder here: in the menu bar, the Dock label, its windows' titles
    ("Downloads — Finder") and its sidebar (Favorites, Shared, Recents, Locations)."""
    msgs = HOME / ".local/share/locale" / LANG_VARIANT / "LC_MESSAGES"
    for po in sorted((HERE / "locale").glob("*.po")):
        mo = msgs / (po.stem + ".mo")
        if not mo.exists() or mo.stat().st_mtime < po.stat().st_mtime:
            msgs.mkdir(parents=True, exist_ok=True)
            if subprocess.run(["msgfmt", "-o", str(mo), str(po)]).returncode == 0:
                log(f"Finder: {po.stem} names in place")
    env = Path(tree) / "plasma-workspace/env/kali-looks-finder.sh"
    if not env.exists() or env.read_text() != ENV_SCRIPT:
        env.parent.mkdir(parents=True, exist_ok=True)
        env.write_text(ENV_SCRIPT)
        log("Finder: names on for this look")
    # the launcher entry (menu bar and Dock show its name); kali-looks keeps it in place
    # only while this look runs, like XP's and Windows 7's own names for it
    system = Path("/usr/share/applications/org.kde.dolphin.desktop")
    own = HOME / ".local/share/applications/org.kde.dolphin.desktop"
    if system.exists():
        lines = []
        for line in system.read_text().splitlines():
            if re.match(r"Name\[[^\]]+\]=", line):
                continue
            lines.append("Name=Finder" if line.startswith("Name=") else line)
        text = "# kali-looks: Finder in the macOS Tahoe look (made from Dolphin's own entry)\n" + "\n".join(lines) + "\n"
        if not own.exists() or own.read_text() != text:
            own.parent.mkdir(parents=True, exist_ok=True)
            own.write_text(text)
            log("Finder: menu bar and Dock name")


# --- Windows 7's window effects stay out of this look ----------------------------------
# AeroThemePlasma installs these system-wide and several are on by default, so they ran
# here too (Aero login, minimize "squash", popups, thumbnails...).
WINDOWS_EFFECTS = ("aeroglassblur", "aeroglide", "smodsnap", "smodglow", "smodpeekeffect",
                   "aeroshell-thumbnails", "dimscreenaero", "fadingpopupsaero", "loginaero", "squashaero")


def no_windows_effects(tree):
    path = Path(tree) / "kwinrc"
    if not path.exists():
        return
    cfg = KConfig(path)
    for effect in WINDOWS_EFFECTS:
        cfg.set(["Plugins"], effect + "Enabled", "false")
    if cfg.save():
        log("KWin: Windows 7's effects off in this look")


def plasma_script(path):
    """Runs a Plasma desktop script; again while Plasma is still starting (no answer
    yet, or the script says "not ready")."""
    import time
    q = shutil.which("qdbus6") or shutil.which("qdbus")
    if not q:
        return ""
    out = ""
    for _ in range(60):
        r = subprocess.run([q, "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript",
                            Path(path).read_text()], capture_output=True, text=True)
        out = r.stdout.strip()
        if r.returncode == 0 and "not ready" not in out:
            return out
        time.sleep(1)
    return out


def screens_live():
    """The menu bar on every screen (screens.js), at login and whenever screens are
    plugged in or rearranged while the session runs."""
    import time
    # Plasma puts its panels on their screens in the first seconds after it starts:
    # judging before that, a screen can look bare and get a second menu bar.
    for _ in range(60):
        age = subprocess.run(["ps", "-o", "etimes=", "-C", "plasmashell"], capture_output=True, text=True).stdout.split()
        if age:
            age = min(int(a) for a in age)
            if age >= 15:
                break
            time.sleep(15 - age)
        else:
            time.sleep(1)
    out = plasma_script(HERE / "screens.js")
    m = re.search(r"added: *(\S*)", out or "")
    r = re.search(r"removed: *(\d+)", out or "")
    if not m or (not m.group(1) and not (r and int(r.group(1)))):
        return
    log(out)
    # How Plasma draws a bar (glass behind each item) is read when Plasma starts: give
    # new bars the main bar's look for the next start. Plasma is never stopped or
    # restarted from here: a restart can't start it again once Remote Desktop has taken
    # DISPLAY out of the session's environment, and the screen stays black.
    tree = (HOME / ".config").resolve()
    menu_bar_views(KConfig(tree / "plasma-org.kde.plasma.desktop-appletsrc"), tree)


WALLPAPER_STATE = HOME / ".local/share/kali-looks/tahoe-wallpaper.json"
WALLPAPER_READ = """(function () {
  var out = [];
  desktops().forEach(function (d) {
    if (d.screen < 0) return;
    d.currentConfigGroup = ["Wallpaper", d.wallpaperPlugin, "General"];
    var keys = d.configKeys.slice().sort(), cfg = {};
    for (var k = 0; k < keys.length; k++) cfg[keys[k]] = String(d.readConfig(keys[k]));
    out.push({id: d.id, screen: d.screen, plugin: d.wallpaperPlugin, cfg: cfg});
  });
  print(JSON.stringify(out));
})();"""


def wallpaper_sync():
    """A wallpaper picked on one screen goes on every screen. Runs whenever Plasma
    saves its desktop settings: the screen whose wallpaper differs from the one last
    shared is the one you just changed, and the others take it."""
    q = shutil.which("qdbus6") or shutil.which("qdbus")
    if not q:
        return
    def plasma(script):
        r = subprocess.run([q, "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", script],
                           capture_output=True, text=True)
        return r.stdout.strip() if r.returncode == 0 else None
    out = plasma(WALLPAPER_READ)
    try:
        desks = json.loads(out) if out else []
    except ValueError:
        return
    if not desks:
        return
    key = lambda d: json.dumps({"plugin": d["plugin"], "cfg": d["cfg"]}, sort_keys=True)
    try:
        last = WALLPAPER_STATE.read_text()
    except OSError:
        last = None
    values = {key(d) for d in desks}
    if len(values) == 1:
        new = values.pop()
    else:
        changed = [d for d in desks if key(d) != last]
        # nothing shared yet: the main screen's wins
        if last is None or not changed:
            changed = sorted(desks, key=lambda d: d["screen"])
        picked = {key(d) for d in changed}
        if len(picked) != 1 and last is not None:
            changed = sorted(changed, key=lambda d: d["screen"])
        new = key(changed[0])
        want = json.loads(new)
        script = "(function () { var n = 0; var want = " + json.dumps(want) + ";" + """
  desktops().forEach(function (d) {
    if (d.screen < 0) return;
    if (d.wallpaperPlugin != want.plugin) d.wallpaperPlugin = want.plugin;
    d.currentConfigGroup = ["Wallpaper", want.plugin, "General"];
    var same = true;
    for (var k in want.cfg) if (String(d.readConfig(k)) != want.cfg[k]) same = false;
    if (same) return;
    for (var k in want.cfg) d.writeConfig(k, want.cfg[k]);
    d.reloadConfig(); n++;
  });
  print(n);
})();"""
        n = plasma(script)
        log(f"wallpaper shared to {n} more screen(s): {want['cfg'].get('Image', want['plugin'])}")
    if new != last:
        WALLPAPER_STATE.parent.mkdir(parents=True, exist_ok=True)
        WALLPAPER_STATE.write_text(new)


def screens_watcher(tree):
    """Runs screens_live whenever KDE saves a screen layout (a screen plugged in,
    unplugged or moved). The unit lives in this look's own config, so it only runs
    in the Tahoe session."""
    unit_dir = Path(tree) / "systemd/user"
    wants = unit_dir / "default.target.wants"
    wants.mkdir(parents=True, exist_ok=True)
    units = {
        "kali-looks-tahoe-screens.path": """[Unit]
Description=kali-looks: the Tahoe menu bar on every screen, when screens change

[Path]
PathChanged=%h/.local/share/kscreen
Unit=kali-looks-tahoe-screens.service

[Install]
WantedBy=default.target
""",
        "kali-looks-tahoe-screens.service": f"""[Unit]
Description=kali-looks: the Tahoe menu bar on every screen

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 3
ExecStart=/usr/bin/python3 {HERE / 'tahoe-finish.py'} --screens
""",
        "kali-looks-tahoe-wallpaper.path": """[Unit]
Description=kali-looks: a wallpaper picked on one screen goes on every screen

[Path]
PathChanged=%h/.config/plasma-org.kde.plasma.desktop-appletsrc
Unit=kali-looks-tahoe-wallpaper.service

[Install]
WantedBy=default.target
""",
        "kali-looks-tahoe-wallpaper.service": f"""[Unit]
Description=kali-looks: the same wallpaper on every screen

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 1
ExecStart=/usr/bin/python3 {HERE / 'tahoe-finish.py'} --wallpaper
""",
    }
    for name, text in units.items():
        f = unit_dir / name
        if not f.exists() or f.read_text() != text:
            f.write_text(text)
            log(f"wrote {name}")
    for unit in ("kali-looks-tahoe-screens.path", "kali-looks-tahoe-wallpaper.path"):
        link = wants / unit
        if not link.exists():
            link.symlink_to("../" + unit)


def wallpaper_repaint():
    """After screens change, every screen draws its wallpaper again. When Plasma rebuilds
    a screen's desktop (screen order changed, a screen plugged back in), the new one can
    keep showing the Tahoe default although its settings name your picture; setting the
    picture again makes it draw."""
    q = shutil.which("qdbus6") or shutil.which("qdbus")
    if not q:
        return
    script = """(function () { var n = 0;
  desktops().forEach(function (d) {
    if (d.screen < 0 || d.wallpaperPlugin != "org.kde.image") return;
    d.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    var img = d.readConfig("Image");
    if (!img) return;
    d.writeConfig("Image", ""); d.reloadConfig();
    d.writeConfig("Image", img); d.reloadConfig(); n++;
  });
  print(n);
})();"""
    r = subprocess.run([q, "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", script],
                       capture_output=True, text=True)
    if r.returncode == 0:
        log(f"wallpaper drawn again on {r.stdout.strip()} screen(s)")


def main():
    if sys.argv[1:] == ["--screens"]:
        screens_live()
        wallpaper_repaint()
        return
    if sys.argv[1:] == ["--wallpaper"]:
        wallpaper_sync()
        return
    if sys.argv[1:] == ["--live"]:
        # once the session is up: the watchers on, then every screen checked
        subprocess.run(["systemctl", "--user", "daemon-reload"], check=False)
        subprocess.run(["systemctl", "--user", "start", "kali-looks-tahoe-screens.path",
                        "kali-looks-tahoe-wallpaper.path"], check=False)
        screens_live()
        wallpaper_sync()
        return
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    tree = sys.argv[1]
    screens_watcher(tree)
    install_plasmoids()
    kvantum(tree)
    glass(tree)
    no_windows_effects(tree)
    no_bell()
    wallpaper_defaults()
    menu_bar(tree)
    desktop_menu(tree)
    dock(tree)
    dock_hover()
    dock_dots()
    spotlight(tree)
    finder_names(tree)
    subprocess.run([sys.executable, str(Path(__file__).resolve().parent / "lockscreen.py"), tree])


if __name__ == "__main__":
    main()
