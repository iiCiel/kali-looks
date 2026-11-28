#!/usr/bin/env python3
"""kali-looks: every desktop of a look gets the look's wallpaper.

A Plasma desktop with no wallpaper image of its own shows Plasma's stock "Next"
picture (the blue one): a screen the look's setup never saw, a screen plugged in
later, or a theme whose default wallpaper can't be found. This fills in the look's
own wallpaper on those desktops only; a wallpaper you picked yourself is kept.

  wallpapers.py config <appletsrc> <wallpaper>   before Plasma starts (no blue flash)
  wallpapers.py lock <look config tree> <wallpaper>  the lock screen, if the look sets none
  wallpapers.py script <wallpaper>               Plasma desktop script for a running session
"""
import json
import re
import subprocess
import sys

DESKTOP_PLUGINS_NOT = ("org.kde.panel", "org.kde.plasma.private.systemtray", "org.kde.plasma.systemtray")


def kread(path, groups, key):
    cmd = ["kreadconfig6", "--file", path]
    for g in groups:
        cmd += ["--group", g]
    return subprocess.run(cmd + ["--key", key], capture_output=True, text=True).stdout.strip()


def kwrite(path, groups, key, value):
    cmd = ["kwriteconfig6", "--file", path]
    for g in groups:
        cmd += ["--group", g]
    subprocess.run(cmd + ["--key", key, value], check=True)


def fill_config(path, wallpaper):
    try:
        text = open(path, encoding="utf-8").read()
    except FileNotFoundError:
        return 0
    filled = 0
    for cid in sorted(set(re.findall(r"^\[Containments\]\[(\d+)\]$", text, re.M)), key=int):
        base = ["Containments", cid]
        plugin = kread(path, base, "plugin")
        if not plugin or plugin in DESKTOP_PLUGINS_NOT:
            continue
        if kread(path, base, "formfactor") not in ("", "0"):
            continue
        if kread(path, base, "wallpaperplugin") not in ("", "org.kde.image"):
            continue
        wp = base + ["Wallpaper", "org.kde.image", "General"]
        if kread(path, wp, "Image"):
            continue
        kwrite(path, base, "wallpaperplugin", "org.kde.image")
        kwrite(path, wp, "Image", wallpaper)
        filled += 1
    return filled


def fill_lockscreen(tree, wallpaper):
    """The lock screen's picture comes from Kali's /etc/xdg/kscreenlockerrc (its blue
    login background) unless the look's own kscreenlockerrc names one."""
    path = f"{tree}/kscreenlockerrc"
    wp = ["Greeter", "Wallpaper", "org.kde.image", "General"]
    if kread(path, wp, "Image") and kread(path, wp, "Image") != "/usr/share/desktop-base/kali-theme/login/background":
        # kreadconfig also sees /etc/xdg; only a value of the look's own counts
        try:
            if "Image=" in open(path, encoding="utf-8").read():
                return 0
        except FileNotFoundError:
            pass
    kwrite(path, ["Greeter"], "WallpaperPlugin", "org.kde.image")
    kwrite(path, wp, "Image", wallpaper)
    return 1


def script(wallpaper):
    # A running Plasma: desktops without an image get the look's wallpaper.
    return """
    (function () {
      var wp = %s, g = ["Wallpaper", "org.kde.image", "General"], n = 0, ds = desktops();
      for (var i = 0; i < ds.length; i++) {
        var d = ds[i];
        if (d.wallpaperPlugin != "org.kde.image") continue;
        d.currentConfigGroup = g;
        if (String(d.readConfig("Image") || "") != "") continue;
        d.writeConfig("Image", wp); d.reloadConfig(); n++;
      }
      print(n);
    })();""" % json.dumps(wallpaper)


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "config":
        print(fill_config(sys.argv[2], sys.argv[3]))
    elif len(sys.argv) == 4 and sys.argv[1] == "lock":
        print(fill_lockscreen(sys.argv[2], sys.argv[3]))
    elif len(sys.argv) == 3 and sys.argv[1] == "script":
        print(script(sys.argv[2]))
    else:
        sys.exit(__doc__)
