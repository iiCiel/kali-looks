#!/usr/bin/env python3
"""kali-looks: Chromium-based apps (Claude, Chrome, Brave, Discord, VS Code...) stay
signed in whichever look you log into.

They encrypt their saved logins with a key from the desktop's password store, and
pick the store from the desktop: KWallet under KDE Plasma (the Windows and macOS
Tahoe looks), GNOME Keyring under Xfce (your own macOS desktop). Each look then
couldn't read what the other saved, so every switch signed you out. Their launchers
now always ask for GNOME Keyring (--password-store=gnome-libsecret), the store that
runs in every session. The desktop portal's secrets (asked for by other apps) come from
GNOME Keyring in every look too. Run at each login with the look's config folder.

Each app's launcher is copied into ~/.local/share/applications with the flag added
(marked X-KaliLooks, and made again from the system's copy at every login so app
updates come through); a launcher that's already yours there just gets the flag.
"""
import os
import re
import shlex
import shutil
from pathlib import Path

FLAG = "--password-store=gnome-libsecret"
MARK = "X-KaliLooks=same-keyring"
HOME = Path.home()
LOCAL = HOME / ".local/share/applications"
SYSTEM = [Path("/usr/share/applications"), Path("/usr/local/share/applications"),
          Path("/var/lib/flatpak/exports/share/applications")]


def program(exec_line):
    try:
        words = shlex.split(exec_line)
    except ValueError:
        return None, None
    i = 0
    if words and os.path.basename(words[0]) == "env":
        i = 1
        while i < len(words) and "=" in words[i] and not words[i].startswith("-"):
            i += 1
    if i >= len(words):
        return None, None
    return words[i], i


# Launchers that open whichever browser you've chosen: not an app of their own.
GENERIC = {"x-www-browser", "sensible-browser", "xdg-open", "exo-open", "gio", "kde-open", "gnome-www-browser"}


def chromium_based(prog):
    if not prog or os.path.basename(prog) in GENERIC:
        return False
    path = shutil.which(prog) if prog and not prog.startswith("/") else prog
    if not path or not os.path.exists(path):
        return False
    d = Path(os.path.realpath(path)).parent
    return any((d / f).exists() for f in ("chrome_100_percent.pak", "v8_context_snapshot.bin", "snapshot_blob.bin"))


def with_flag(text):
    out = []
    for line in text.splitlines():
        if line.startswith("Exec=") and FLAG not in line:
            prog, i = program(line[5:])
            if prog:
                # the flag goes right after the program, the rest of the line untouched
                rest = line[5:]
                pos = 0
                for _ in range(i + 1):
                    rest_from = rest[pos:].lstrip()
                    pos = len(rest) - len(rest_from)
                    if rest_from.startswith('"'):
                        end = rest_from.find('"', 1)
                        while end > 0 and rest_from[end - 1] == "\\":
                            end = rest_from.find('"', end + 1)
                        pos += end + 1
                    else:
                        sp = rest_from.find(" ")
                        pos += len(rest_from) if sp < 0 else sp
                line = "Exec=" + rest[:pos] + " " + FLAG + rest[pos:]
        out.append(line)
    return "\n".join(out) + "\n"


BIN = HOME / ".local/bin"


def wrapper(name):
    """A launcher found by name (Claude's own, which it writes itself) runs this, first
    on the PATH, with the flag."""
    real = None
    for d in os.environ.get("PATH", "/usr/bin:/bin").split(":") + ["/usr/bin", "/bin"]:
        c = Path(d) / name
        if d and Path(d).resolve() != BIN.resolve() and c.exists() and os.access(c, os.X_OK):
            real = c
            break
    if not real:
        return
    f = BIN / name
    text = f"#!/bin/sh\n# {MARK}: see kali-looks/lib/same-keyring.py\nexec {shlex.quote(str(real))} {FLAG} \"$@\"\n"
    if f.exists() and MARK not in f.read_text():
        return  # yours
    if not f.exists() or f.read_text() != text:
        BIN.mkdir(parents=True, exist_ok=True)
        f.write_text(text)
        f.chmod(0o755)


def portals(cfg):
    """Apps that ask the desktop portal for a secret get GNOME Keyring too, in every
    look (KDE's would otherwise answer under Plasma -- and start under Xfce)."""
    sysdir = Path("/usr/share/xdg-desktop-portal")
    if not (sysdir / "portals/gnome-keyring.portal").exists():
        return
    out = Path(cfg) / "xdg-desktop-portal"
    for conf in sorted(sysdir.glob("*-portals.conf")):
        mine = out / conf.name
        # (a file of your own without our line is kept, with the line added)
        base = mine.read_text() if mine.exists() else conf.read_text()
        lines = [l for l in base.splitlines() if not l.startswith("org.freedesktop.impl.portal.Secret=")]
        if "[preferred]" not in lines:
            lines.insert(0, "[preferred]")
        lines.insert(lines.index("[preferred]") + 1, "org.freedesktop.impl.portal.Secret=gnome-keyring")
        text = "\n".join(lines).rstrip("\n") + "\n"
        if not mine.exists() or mine.read_text() != text:
            out.mkdir(parents=True, exist_ok=True)
            mine.write_text(text)


def main():
    import sys
    if len(sys.argv) > 1:
        portals(sys.argv[1])
    LOCAL.mkdir(parents=True, exist_ok=True)
    done = []
    seen = set()
    for d in SYSTEM:
        if not d.is_dir():
            continue
        for f in sorted(d.glob("*.desktop")):
            if f.name in seen:
                continue
            seen.add(f.name)
            try:
                text = f.read_text()
            except (OSError, UnicodeDecodeError):
                continue
            m = re.search(r"^Exec=(.*)$", text, re.M)
            if not m or not chromium_based(program(m.group(1))[0]):
                continue
            prog = program(m.group(1))[0]
            if "/" not in prog:
                wrapper(prog)
            local = LOCAL / f.name
            if local.exists() and MARK not in local.read_text():
                # yours (or the app's own): just the flag
                old = local.read_text()
                new = with_flag(old)
                if new != old:
                    local.write_text(new)
                    done.append(f.name)
                continue
            new = with_flag(text)
            new = new.replace("[Desktop Entry]\n", f"[Desktop Entry]\n{MARK}\n", 1)
            if not local.exists() or local.read_text() != new:
                local.write_text(new)
                done.append(f.name)
    # launchers of ours whose app was removed
    for local in LOCAL.glob("*.desktop"):
        if local.name not in seen and MARK in local.read_text():
            local.unlink()
    if done:
        print("same keyring for: " + ", ".join(done))


if __name__ == "__main__":
    main()
