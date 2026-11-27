#!/usr/bin/env python3
"""kali-looks: Windows 7 session fixes.

  w7-finish.py CONFIG_DIR   before the session starts (Plasma not running yet)
  w7-finish.py --live       once the session is up (from after-start)
  w7-finish.py --screens    when screens are plugged in or rearranged

- Windows 7's scale on a high-resolution panel (Windows 7 offered 125%/150% for
  exactly this): the panel's dpi / 96, as for Windows XP.
- The clock and dates in US English (5:15 PM over 11/27/2026) instead of the "C"
  locale AeroShell's first-run setup left (14:51, 25 11 2026).
- The notification area and the desktop's right-click menu as Windows 7's.
- A taskbar on every screen, and the Windows 7 wallpaper on screens plugged in later.
- The Start menu's list like Windows 7's: its usual programs' counterparts (Calculator,
  Snipping Tool, Media Player, Notepad...) after yours (set once; yours to change).
"""
import importlib.util
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
HOME = Path.home()
_spec = importlib.util.spec_from_file_location("xp_finish", HERE.parent / "winxp/xp-finish.py")
xp = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(xp)
STAMP = "win7-scale.auto"


def log(msg):
    print(f"w7-finish: {msg}", flush=True)


def system_lang():
    try:
        m = re.search(r'^LANG="?([^"\n]+)"?', Path("/etc/default/locale").read_text(), re.M)
        if m:
            return m.group(1)
    except OSError:
        pass
    return "en_US.UTF-8"


def locale(cfg):
    f = Path(cfg) / "plasma-localerc"
    text = f.read_text() if f.exists() else ""
    m = re.search(r"^LANG=(.*)$", text, re.M)
    if m and not m.group(1).startswith(("C", "POSIX")):
        return  # yours
    xp.ini_set(f, ["Formats"], {"LANG": system_lang()})
    log(f"dates and times in {system_lang()}")


def clock(cfg):
    """Windows 7's clock: the time over the date, the date as 11/27/2026 (Plasma's
    short date has a two-digit year)."""
    sys.path.insert(0, str(HERE.parent / "winxp"))
    import xp_taskbars
    f = Path(cfg) / "plasma-io.gitgud.wackyideas.desktop-appletsrc"
    if not f.exists():
        return
    ini = xp_taskbars.Ini(f.read_text())
    changed = False
    for name in ini.names():
        if ini.get(name, "plugin") == "io.gitgud.wackyideas.digitalclocklite":
            g = name + "][Configuration][Appearance"
            for key, value in (("dateFormat", "customDate"), ("customFormat", "M/d/yyyy")):
                if ini.get(g, key) != value:
                    ini.set(g, key, value)
                    changed = True
    if changed:
        f.write_text(ini.text())
        log("clock date as 11/27/2026")


def desktop_menu(cfg):
    """The desktop's right-click menu as Windows 7's: no KDE "Enter Edit Mode"."""
    sys.path.insert(0, str(HERE.parent / "winxp"))
    import xp_taskbars
    f = Path(cfg) / "plasma-io.gitgud.wackyideas.desktop-appletsrc"
    if not f.exists():
        return
    ini = xp_taskbars.Ini(f.read_text())
    changed = False
    for name in list(ini.names()):
        if name.startswith("ActionPlugins][") and name.count("][") == 1 and ini.get(name, "RightButton;NoModifier") == "org.kde.contextmenu":
            g = name + "][RightButton;NoModifier"
            for key in ("desktop edit mode", "edit mode"):
                if ini.get(g, key) != "false":
                    ini.set(g, key, "false")
                    changed = True
    if changed:
        f.write_text(ini.text())
        log("desktop menu without Enter Edit Mode")


TRAY_SHOWN = ["io.gitgud.wackyideas.notifications", "io.gitgud.wackyideas.battery",
              "io.gitgud.wackyideas.networkmanagement", "io.gitgud.wackyideas.volume"]
TRAY_HIDDEN = ["org.kde.plasma.clipboard", "org.kde.kscreen", "org.kde.plasma.bluetooth",
               "org.kde.plasma.devicenotifier", "org.kde.plasma.mediacontroller", "org.kde.plasma.brightness",
               "org.kde.plasma.cameraindicator", "org.kde.plasma.manage-inputmethod",
               "org.kde.plasma.keyboardindicator", "org.kde.plasma.weather", "org.kde.plasma.vault",
               "org.kde.kupapplet"]


def tray(cfg):
    """The notification area as Windows 7's: Action Center, power, network and volume
    in sight (the power meter even when charged), the rest behind the arrow."""
    sys.path.insert(0, str(HERE.parent / "winxp"))
    import xp_taskbars
    f = Path(cfg) / "plasma-io.gitgud.wackyideas.desktop-appletsrc"
    if not f.exists():
        return
    ini = xp_taskbars.Ini(f.read_text())
    changed = False
    for name in list(ini.names()):
        if ini.get(name, "plugin") == "io.gitgud.wackyideas.systemtray":
            g = name + "][General"
            for key, items in (("shownItems", TRAY_SHOWN), ("hiddenItems", TRAY_HIDDEN)):
                if ini.get(g, key) != ",".join(items):
                    ini.set(g, key, ",".join(items))
                    changed = True
    if changed:
        f.write_text(ini.text())
        log("notification area as Windows 7's")


START_SIDE = {"Home directory": 1, "Documents": 1, "Pictures": 1, "Music": 1, "Games": 1, "Computer": 1,
              "Control Panel": 1, "Devices and Printers": 1, "Default Programs": 1, "Help and Support": 1}


def start_side(cfg):
    """The Start menu's right column as Windows 7's: Games between Music and Computer
    (AeroShell has it, off by default). Only added where you haven't turned it off."""
    sys.path.insert(0, str(HERE.parent / "winxp"))
    import xp_taskbars
    f = Path(cfg) / "plasma-io.gitgud.wackyideas.desktop-appletsrc"
    if not f.exists():
        return
    ini = xp_taskbars.Ini(f.read_text())
    changed = False
    for name in list(ini.names()):
        if ini.get(name, "plugin") != SEVENSTART:
            continue
        g = name + "][Configuration][General"
        have = ini.get(g, "sidePanelVisibility")
        try:
            vis = json.loads(have) if have else dict(START_SIDE, Games=0)
        except ValueError:
            continue
        if "Games" not in vis or (not have):
            vis["Games"] = 1
            ini.set(g, "sidePanelVisibility", json.dumps(vis, separators=(",", ":")))
            changed = True
    if changed:
        f.write_text(ini.text())
        log("Start menu: Games")


def title_buttons(cfg):
    """Windows 7's title bar buttons: minimize, maximize, close (no "?" help button,
    which KDE's default adds). Only while you haven't picked your own."""
    import subprocess
    rc = cfg / "kwinrc"
    have = subprocess.run(["kreadconfig6", "--file", str(rc), "--group", "org.kde.kdecoration2",
                           "--key", "ButtonsOnRight"], capture_output=True, text=True).stdout.strip()
    if have in ("", "HIAX"):
        subprocess.run(["kwriteconfig6", "--file", str(rc), "--group", "org.kde.kdecoration2",
                        "--key", "ButtonsOnRight", "IAX"])
        log("title bar buttons: minimize, maximize, close")


def alt_tab(cfg):
    """Alt+Tab as on Windows 7: on, with AeroShell's Windows 7 switcher (window
    thumbnails in a glass box, centred on the screen). The look's first setup left the
    shortcut off, and KDE's fallback switcher opens in the corner of the left screen."""
    import subprocess
    rc = cfg / "kglobalshortcutsrc"
    if rc.exists():
        text = rc.read_text()
        new = re.sub(r"^Walk Through Windows=none,", r"Walk Through Windows=Alt+Tab\\tMeta+Tab,", text, flags=re.M)
        new = re.sub(r"^Walk Through Windows \(Reverse\)=none,",
                     r"Walk Through Windows (Reverse)=Alt+Shift+Tab\\tMeta+Shift+Tab,", new, flags=re.M)
        if new != text:
            rc.write_text(new)
            log("Alt+Tab on")
    kwin = cfg / "kwinrc"
    have = subprocess.run(["kreadconfig6", "--file", str(kwin), "--group", "TabBox", "--key", "LayoutName"],
                          capture_output=True, text=True).stdout.strip()
    if not have and Path("/usr/share/kwin/tabbox/thumbnail_aero").is_dir():
        subprocess.run(["kwriteconfig6", "--file", str(kwin), "--group", "TabBox",
                        "--key", "LayoutName", "thumbnail_aero"])
        log("Alt+Tab switcher: Windows 7's")


# Kali's own Start menu favourites, which KDE puts back when it sets the menu up again
# (a new activity, a reset menu): not on a Windows 7 Start menu.
KALI_PINS = re.compile(r"kali-|exploit|offsec|vulnhub|root-terminal|org\.kde\.kate\.desktop|"
                       r"systemsettings\.desktop|org\.kde\.discover")


def prune_pins():
    import sqlite3
    import subprocess
    agent = "org.kde.plasma.favorites.applications"
    db = HOME / ".local/share/kactivitymanagerd/resources/database"
    try:
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        rows = con.execute("select targettedResource, usedActivity from ResourceLink "
                           "where initiatingAgent=?", (agent,)).fetchall()
        con.close()
    except Exception:
        return
    for res, act in rows:
        if KALI_PINS.search(res):
            subprocess.run(["gdbus", "call", "--session", "-d", "org.kde.ActivityManager", "-o",
                            "/ActivityManager/Resources/Linking", "-m",
                            "org.kde.ActivityManager.ResourcesLinking.UnlinkResourceFromActivity",
                            agent, res, act or ":global"], capture_output=True)
            log(f"Start menu: dropped Kali's {res}")


SEVENSTART = "io.gitgud.wackyideas.SevenStart"
SEVENTASKS = "io.gitgud.wackyideas.seventasks"
POWER_WORDS = {"Log Out": "Log off", "Switch User": "Switch user", "Shut Down": "Shut down"}

# Windows 7's taskbar menu (right-click on the taskbar): Cascade windows, Show windows
# stacked, Show windows side by side, Show the desktop, Start Task Manager, Lock the
# taskbar, Properties. AeroShell's has KDE's items, and its "Task Manager" runs
# ksysguard, which Plasma 6 doesn't have.
TASKBAR_MENU = r"""    Plasmoid.contextualActions: [ // kali-looks: Windows 7's taskbar menu
        PlasmaCore.Action {
            text: i18n("Cascade windows")
            onTriggered: menu_executable.exec("bash '@ARRANGE@' cascade")
        },
        PlasmaCore.Action {
            text: i18n("Show windows stacked")
            onTriggered: menu_executable.exec("bash '@ARRANGE@' stack")
        },
        PlasmaCore.Action {
            text: i18n("Show windows side by side")
            onTriggered: menu_executable.exec("bash '@ARRANGE@' side")
        },
        PlasmaCore.Action {
            text: i18n("Show the desktop")
            onTriggered: menu_executable.exec("qdbus6 org.kde.kglobalaccel /component/kwin invokeShortcut 'Show Desktop'")
        },
        PlasmaCore.Action { isSeparator: true },
        PlasmaCore.Action {
            text: i18n("Start Task Manager")
            onTriggered: menu_executable.exec("plasma-systemmonitor")
        },
        PlasmaCore.Action { isSeparator: true },
        PlasmaCore.Action {
            // Unlocking the taskbar is Plasma's panel edit mode
            text: i18n("Lock the taskbar")
            checkable: true
            checked: true
            onTriggered: {
                checked = true;
                Plasmoid.containment.internalAction("configure")?.trigger();
            }
        },
        PlasmaCore.Action {
            text: i18n("Properties")
            onTriggered: Plasmoid.internalAction("configure")?.trigger()
        }
    ]
    // kali-looks: Plasma turns some of KDE's items back on, so again as the menu opens
    Connections {
        target: Plasmoid
        function onContextualActionsAboutToShow() { tasks.kaliHideKdeItems(); }
    }
    function kaliHideKdeItems() {
        for (const a of [Plasmoid.internalAction("configure"), Plasmoid.internalAction("alternatives"),
                         Plasmoid.containment.internalAction("add widgets"),
                         Plasmoid.containment.internalAction("configure")])
            if (a) a.visible = false;
        // Plasma adds Show Alternatives whenever it's enabled
        const alt = Plasmoid.internalAction("alternatives");
        if (alt) alt.enabled = false;
    }
"""
# Only Windows 7's items in that menu: KDE's own (Configure, Show Alternatives, Add or
# Manage Widgets, Show Panel Configuration) hidden there; Properties and Lock the
# taskbar reach them.
TASKBAR_HIDE = "        kaliHideKdeItems(); // kali-looks\n"


def _start_menu_edit(text):
    old = 'text: "       " + model.display + "      "'
    if text.count(old) != 1:
        return None
    words = json.dumps(POWER_WORDS)
    return text.replace(old, f'text: "       " + ({words}[model.display] || model.display) + "      " // kali-looks')


def _taskbar_edit(text):
    m = re.search(r"^    Plasmoid\.contextualActions: \[\n.*?^    \]\n", text, re.M | re.S)
    hook = "    Component.onCompleted: {\n        TaskTools.taskManagerInstanceCount += 1;\n"
    if not m or text.count(hook) != 1:
        return None
    text = text[:m.start()] + TASKBAR_MENU.replace("@ARRANGE@", str(HERE / "arrange.sh")) + text[m.end():]
    return text.replace(hook, hook + TASKBAR_HIDE)


# AeroShell widgets we change: (widget, file, edit). Each is a copy of the installed
# widget with the change, made again from the installed one at every login (so an
# AeroShell update comes through) and linked in only while the Windows 7 look runs.
def _jumplist_edit(text):
    """Windows 7's words in a taskbar button's jump list."""
    pairs = [('text: "Pin program to taskbar"', 'text: "Pin this program to taskbar"'),
             ('text: i18n("Unpin program from taskbar")', 'text: i18n("Unpin this program from taskbar")')]
    if any(text.count(a) != 1 for a, _ in pairs):
        return None
    for a, b in pairs:
        text = text.replace(a, b)
    return text


WIN7_PICTURE = Path("/usr/share/sddm/themes/sddm-theme-mod/Assets/user.png")  # AeroShell's copy


def _picture_edit(text):
    """The Start menu's user picture: Windows 7's default (the orange flower, which
    AeroShell ships) while yours is still Kali's stock one (its dragon logo). A picture
    you set yourself shows instead."""
    old = "source: kuser.faceIconUrl.toString()\n"
    if text.count(old) != 1:
        return None
    face, stock = HOME / ".face", Path("/etc/skel/.face")
    try:
        is_stock = not face.exists() or (stock.exists() and face.read_bytes() == stock.read_bytes())
    except OSError:
        is_stock = False
    if not (is_stock and WIN7_PICTURE.exists()):
        return text
    return text.replace(old, f'source: "file://{WIN7_PICTURE}" // kali-looks: Windows 7\'s picture\n')


PATCHED = [
    (SEVENSTART, {"contents/ui/MenuRepresentation.qml": _start_menu_edit,
                  "contents/ui/FloatingIcon.qml": _picture_edit}, "Start menu: Windows 7's"),
    (SEVENTASKS, {"contents/ui/main.qml": _taskbar_edit, "contents/ui/TasksMenu.qml": _jumplist_edit},
     "taskbar menus: Windows 7's"),
]


def patch_widgets():
    import shutil
    for widget, edits, what in PATCHED:
        src = Path("/usr/share/plasma/plasmoids") / widget
        dest = HOME / ".local/share/plasma/plasmoids" / widget
        if not src.is_dir():
            continue
        want = {}
        for qml, edit in edits.items():
            new = edit((src / qml).read_text()) if (src / qml).is_file() else None
            if new is None:
                log(f"{widget}: {qml} changed upstream; left as AeroShell's")
                continue
            want[qml] = new
        if not want:
            continue
        if (dest / "metadata.json").is_file() \
                and (dest / "metadata.json").read_text() == (src / "metadata.json").read_text() \
                and all((dest / q).is_file() and (dest / q).read_text() == t for q, t in want.items()):
            continue
        target = dest.resolve() if dest.is_symlink() else dest
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(src, target, symlinks=True)
        for q, t in want.items():
            (target / q).write_text(t)
        log(what)


def watcher(cfg):
    """Re-run --screens when screens change (a unit of this look's own, stopped when
    you switch to another look)."""
    unit_dir = Path(cfg) / "systemd/user"
    wants = unit_dir / "default.target.wants"
    wants.mkdir(parents=True, exist_ok=True)
    (unit_dir / "kali-looks-w7-screens.path").write_text("""[Unit]
Description=kali-looks: Windows 7 taskbar and wallpaper on every screen, when screens change

[Path]
PathChanged=%h/.local/share/kscreen
Unit=kali-looks-w7-screens.service

[Install]
WantedBy=default.target
""")
    (unit_dir / "kali-looks-w7-screens.service").write_text(f"""[Unit]
Description=kali-looks: Windows 7 taskbar and wallpaper on every screen

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 3
ExecStart=/usr/bin/python3 {HERE / 'w7-finish.py'} --screens
""")
    link = wants / "kali-looks-w7-screens.path"
    if not link.exists():
        link.symlink_to("../kali-looks-w7-screens.path")


def main():
    args = sys.argv[1:]
    if args and args[0] == "--live":
        # Windows 7's Start menu list: the closest things to its own programs
        # (Calculator, Snipping Tool, Media Player, Notepad...) after yours.
        apps = ["com.anthropic.Claude.desktop", "org.kde.dolphin.desktop", "org.kde.konsole.desktop",
                "org.kde.kcalc.desktop", "org.kde.spectacle.desktop", "org.kde.dragonplayer.desktop",
                "org.xfce.mousepad.desktop", "org.kde.plasma-systemmonitor.desktop"]
        xp.set_favorites(["preferred://browser"] + ["applications:" + a for a in apps
                                                    if (Path("/usr/share/applications") / a).exists()],
                         "win7-pins.done", "Windows 7")
        xp.seed_most_used(["com.anthropic.Claude.desktop", "org.kde.dolphin.desktop", "org.kde.konsole.desktop",
                           "org.kde.kcalc.desktop", "org.kde.spectacle.desktop", "org.kde.dragonplayer.desktop",
                           "org.xfce.mousepad.desktop", "org.kde.plasma-systemmonitor.desktop"],
                          "win7-mfu.done", "Windows 7")
        prune_pins()
    if args and args[0] in ("--live", "--screens"):
        xp.screens_live(HERE / "screens.js", STAMP)
        return
    if not args:
        sys.exit(__doc__)
    cfg = Path(args[0])
    locale(cfg)
    clock(cfg)
    desktop_menu(cfg)
    tray(cfg)
    start_side(cfg)
    title_buttons(cfg)
    alt_tab(cfg)
    patch_widgets()
    xp.windows_names()
    xp.screen_scale(cfg, STAMP)
    watcher(cfg)


if __name__ == "__main__":
    main()
