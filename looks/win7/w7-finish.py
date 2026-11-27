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
POWER_WORDS = {"Log Out": "Log off", "Switch User": "Switch user", "Shut Down": "Shut down"}


def start_menu():
    """The Start menu's power menu in Windows 7's words (Log off, Switch user). A copy
    of AeroShell's Start menu with that one change, made again from the installed one at
    every login (so an AeroShell update comes through) and linked in only while the
    Windows 7 look runs."""
    import json
    import shutil
    src = Path("/usr/share/plasma/plasmoids") / SEVENSTART
    dest = HOME / ".local/share/plasma/plasmoids" / SEVENSTART
    if not src.is_dir():
        return
    qml = "contents/ui/MenuRepresentation.qml"
    old = 'text: "       " + model.display + "      "'
    words = json.dumps(POWER_WORDS)
    new = f'text: "       " + ({words}[model.display] || model.display) + "      " // kali-looks'
    text = (src / qml).read_text()
    if text.count(old) != 1:
        return  # AeroShell changed: leave its own
    want = text.replace(old, new)
    if dest.exists() and (dest / qml).exists() and (dest / qml).read_text() == want \
            and (dest / "metadata.json").read_text() == (src / "metadata.json").read_text():
        return
    target = dest.resolve() if dest.is_symlink() else dest
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(src, target, symlinks=True)
    (target / qml).write_text(want)
    log("Start menu: Log off, Switch user")


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
    title_buttons(cfg)
    start_menu()
    xp.windows_names()
    xp.screen_scale(cfg, STAMP)
    watcher(cfg)


if __name__ == "__main__":
    main()
