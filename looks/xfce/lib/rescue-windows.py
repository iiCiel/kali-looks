#!/usr/bin/env python3
"""Bring windows that hang off the screen back onto a monitor.

Run after monitors change (cupertino-xfce-mode monitors). A window that is partly or
wholly outside every monitor is moved onto the monitor it overlaps most (the primary one
if none), and shrunk if it's bigger than that monitor's free area. Maximized windows are
re-maximized on that monitor. Windows that are fully on a screen are left alone.
"""
import sys
import warnings

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("Wnck", "3.0")
warnings.filterwarnings("ignore")
from gi.repository import Gdk, Gtk, Wnck  # noqa: E402

SKIP = {Wnck.WindowType.DESKTOP, Wnck.WindowType.DOCK, Wnck.WindowType.SPLASHSCREEN,
        Wnck.WindowType.MENU, Wnck.WindowType.TOOLBAR, Wnck.WindowType.UTILITY}


def overlap(a, b):
    w = min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0])
    h = min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1])
    return max(w, 0) * max(h, 0)


def main():
    display = Gdk.Display.get_default()
    mons = []
    for i in range(display.get_n_monitors()):
        m = display.get_monitor(i)
        g, wa = m.get_geometry(), m.get_workarea()
        mons.append({"geo": (g.x, g.y, g.width, g.height),
                     "work": (wa.x, wa.y, wa.width, wa.height),
                     "primary": m.is_primary()})
    if not mons:
        return 0
    primary = next((m for m in mons if m["primary"]), mons[0])

    screen = Wnck.Screen.get_default()
    screen.force_update()
    moved = 0
    for win in screen.get_windows():
        if win.get_window_type() in SKIP or win.is_skip_tasklist() or win.is_minimized():
            continue
        x, y, w, h = win.get_geometry()  # includes the frame
        if w <= 0 or h <= 0:
            continue
        rect = (x, y, w, h)
        # fully inside one monitor: fine
        if any(overlap(rect, m["geo"]) == w * h for m in mons):
            continue
        best = max(mons, key=lambda m: overlap(rect, m["geo"]))
        if overlap(rect, best["geo"]) == 0:
            best = primary
        wx, wy, ww, wh = best["work"]
        maximized = win.is_maximized()
        if maximized:
            win.unmaximize()
        nw, nh = min(w, ww), min(h, wh)
        nx = min(max(x, wx), wx + ww - nw)
        ny = min(max(y, wy), wy + wh - nh)
        mask = (Wnck.WindowMoveResizeMask.X | Wnck.WindowMoveResizeMask.Y |
                Wnck.WindowMoveResizeMask.WIDTH | Wnck.WindowMoveResizeMask.HEIGHT)
        win.set_geometry(Wnck.WindowGravity.STATIC, mask, nx, ny, nw, nh)
        if maximized:
            win.maximize()
        moved += 1
        print("rescue-windows: moved %r onto the screen" % win.get_name()[:60], file=sys.stderr)
    # let the requests reach the window manager before we exit
    while Gtk.events_pending():
        Gtk.main_iteration()
    Gdk.Display.get_default().flush()
    return 0


if __name__ == "__main__":
    Gtk.init(sys.argv)
    sys.exit(main())
