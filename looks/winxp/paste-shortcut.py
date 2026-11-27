#!/usr/bin/env python3
"""kali-looks: XP's "Paste Shortcut" -- a link to each copied file, named "Shortcut to …"."""
import os
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse


def target_dir(arg):
    if arg.startswith("file://"):
        return Path(unquote(urlparse(arg).path))
    try:
        out = subprocess.run(["xdg-user-dir", "DESKTOP"], capture_output=True, text=True).stdout.strip()
        if out:
            return Path(out)
    except OSError:
        pass
    return Path.home() / "Desktop"


def main():
    dest = target_dir(sys.argv[1] if len(sys.argv) > 1 else "desktop:/")
    try:
        uris = subprocess.run(["xclip", "-o", "-selection", "clipboard", "-t", "text/uri-list"],
                              capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.TimeoutExpired):
        return
    for line in uris.splitlines():
        line = line.strip()
        if not line.startswith("file://"):
            continue
        src = Path(unquote(urlparse(line).path))
        if not src.exists():
            continue
        name = f"Shortcut to {src.name}"
        link, n = dest / name, 2
        while link.exists() or link.is_symlink():
            link = dest / f"Shortcut ({n}) to {src.name}"
            n += 1
        os.symlink(src, link)


if __name__ == "__main__":
    main()
