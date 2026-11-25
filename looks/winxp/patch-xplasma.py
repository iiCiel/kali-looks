#!/usr/bin/env python3
"""Small fixes kali-looks applies to its unpacked copy of the XPlasma Plus installer.

Run with the installer's folder. Each fix is applied once (marked "kali-looks"), and the
installer's own checksum list is updated so its self-check still passes.
"""
import hashlib
import json
import sys
from pathlib import Path

base = Path(sys.argv[1])
FIXES = [
    # ~/.config is a link to this look's own (plain) folder; ~/.local and ~/.icons are
    # links in the hidden setup session. Its backups are fine with that.
    ("backend.py",
     "   if path.is_symlink():links.add(str(path))",
     "   if path.is_symlink() and path not in {home/'.config',home/'.local',home/'.icons'}:links.add(str(path))  # kali-looks"),
    # Its build-dependency step turned every "deb" line into "deb-src" instead of adding
    # one, so with one-line .list sources (Kali) no binary packages were left.
    ("dependencies.py",
     "   else:text=re.sub(r'^(\\s*)deb\\s',r'\\1deb-src ',text,flags=re.M)",
     "   else:text=text+'\\n'+re.sub(r'^(\\s*)deb\\s',r'\\1deb-src ',text,flags=re.M)  # kali-looks"),
    # Loading/unloading effects in the running KWin is only a live preview; the settings
    # are written either way. Don't fail the install when the (hidden) KWin can't.
    ("payload/tools/xp-behavior.py",
     "    for effect in DISABLED:\n        run(DBUS, 'org.kde.KWin', '/Effects',\n            'org.kde.kwin.Effects.unloadEffect', effect)\n    run(DBUS, 'org.kde.KWin', '/Effects',\n        'org.kde.kwin.Effects.loadEffect', 'fadingpopups')",
     "    for effect in DISABLED:  # kali-looks: live preview only\n        subprocess.run([DBUS, 'org.kde.KWin', '/Effects', 'org.kde.kwin.Effects.unloadEffect', effect], check=False)\n    subprocess.run([DBUS, 'org.kde.KWin', '/Effects', 'org.kde.kwin.Effects.loadEffect', 'fadingpopups'], check=False)"),
]

sums_file = base / "SHA256SUMS.json"
sums = json.loads(sums_file.read_text())
for name, old, new in FIXES:
    f = base / name
    text = f.read_text()
    if new in text:
        continue
    if text.count(old) != 1:
        sys.exit(f"patch-xplasma: expected code not found in {name}")
    f.write_text(text.replace(old, new))
    if name in sums:
        sums[name] = hashlib.sha256(f.read_bytes()).hexdigest()
sums_file.write_text(json.dumps(sums, indent=2) + "\n")
