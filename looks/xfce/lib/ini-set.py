#!/usr/bin/env python3
"""Set, read or delete one key in an INI file, keeping the rest of the file untouched.

  ini-set.py FILE SECTION KEY VALUE     set (prints the previous value, or nothing)
  ini-set.py FILE SECTION KEY --get     print the current value (exit 1 if missing)
  ini-set.py FILE SECTION KEY --delete  remove the key

Used for qterminal.ini and gtk-3.0/settings.ini. configparser isn't used on purpose:
it would rewrite comments, key case and ordering, and Qt's ini escaping.
"""
import os
import re
import sys

SECTION = re.compile(r"\s*\[(.+)\]\s*$")


def main(argv):
    if len(argv) != 5:
        sys.exit(__doc__)
    path, section, key, value = argv[1:]
    lines = open(path).read().splitlines() if os.path.exists(path) else []
    key_re = re.compile(r"\s*" + re.escape(key) + r"\s*=(.*)$")

    cur_sec, found_idx, sec_idx, prev = None, None, None, None
    for i, line in enumerate(lines):
        m = SECTION.match(line)
        if m:
            cur_sec = m.group(1)
            if cur_sec == section:
                sec_idx = i
            continue
        if cur_sec == section:
            k = key_re.match(line)
            if k and found_idx is None:
                found_idx, prev = i, k.group(1).strip()

    if value == "--get":
        if prev is None:
            sys.exit(1)
        print(prev)
        return
    if value == "--delete":
        if found_idx is not None:
            del lines[found_idx]
    elif found_idx is not None:
        lines[found_idx] = f"{key}={value}"
    elif sec_idx is not None:
        # insert at the end of the section
        j = sec_idx + 1
        while j < len(lines) and not SECTION.match(lines[j]):
            j += 1
        while j > sec_idx + 1 and lines[j - 1].strip() == "":
            j -= 1
        lines.insert(j, f"{key}={value}")
    else:
        if lines and lines[-1].strip():
            lines.append("")
        lines += [f"[{section}]", f"{key}={value}"]

    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    if prev is not None:
        print(prev)


if __name__ == "__main__":
    main(sys.argv)
