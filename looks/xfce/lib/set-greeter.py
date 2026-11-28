#!/usr/bin/env python3
"""Set cupertino-xfce keys in the [greeter] section of lightdm-gtk-greeter.conf.

Usage: set-greeter.py <conf-file>
Existing keys (even commented-out ones) are replaced in place; missing keys are added.
Everything else in the file is left as it was.
"""
import re
import sys

WANT = {
    "background": "/usr/share/backgrounds/cupertino-xfce/login.jpg",
    "user-background": "false",
    "theme-name": "WhiteSur-Login",
    "icon-theme-name": "WhiteSur",
    "cursor-theme-name": "WhiteSur-cursors",
    "font-name": "Inter 11",
    "indicators": "~spacer;~clock;~spacer;~session;~a11y;~power;",
    "clock-format": "%a %b %-d  %-I:%M %p",
}

SECTION = re.compile(r"\s*\[(.+)\]\s*$")
KEY = re.compile(r"\s*#?\s*([\w-]+)\s*=")


def main(path: str) -> None:
    with open(path) as fh:
        lines = fh.read().splitlines()

    out, in_greeter, seen, had_greeter = [], False, set(), False
    for line in lines:
        sec = SECTION.match(line)
        if sec:
            if in_greeter:
                out += [f"{k} = {v}" for k, v in WANT.items() if k not in seen]
            in_greeter = sec.group(1) == "greeter"
            had_greeter = had_greeter or in_greeter
            out.append(line)
            continue
        key = KEY.match(line)
        if in_greeter and key and key.group(1) in WANT and key.group(1) not in seen:
            out.append(f"{key.group(1)} = {WANT[key.group(1)]}")
            seen.add(key.group(1))
            continue
        out.append(line)

    if in_greeter:
        out += [f"{k} = {v}" for k, v in WANT.items() if k not in seen]
    if not had_greeter:
        out += ["[greeter]"] + [f"{k} = {v}" for k, v in WANT.items()]

    with open(path, "w") as fh:
        fh.write("\n".join(out) + "\n")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
