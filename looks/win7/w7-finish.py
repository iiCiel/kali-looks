#!/usr/bin/env python3
"""kali-looks: Windows 7 session fixes.

  w7-finish.py CONFIG_DIR   before the session starts (Plasma not running yet)
  w7-finish.py --live       once the session is up (from after-start)
  w7-finish.py --screens    when screens are plugged in or rearranged

- Windows 7's scale on a high-resolution panel (Windows 7 offered 125%/150% for
  exactly this): the panel's dpi / 96, as for Windows XP.
- The clock and dates in US English (5:15 PM over 11/27/2026) instead of the "C"
  locale AeroShell's first-run setup left (14:51, 25 11 2026).
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
    if args and args[0] in ("--live", "--screens"):
        xp.screens_live(HERE / "screens.js", STAMP)
        return
    if not args:
        sys.exit(__doc__)
    cfg = Path(args[0])
    locale(cfg)
    clock(cfg)
    xp.windows_names()
    xp.screen_scale(cfg, STAMP)
    watcher(cfg)


if __name__ == "__main__":
    main()
