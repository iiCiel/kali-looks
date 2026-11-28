#!/usr/bin/env python3
"""kali-looks: menu bar text colored by the wallpaper, as on a Mac.

macOS draws the menu bar's text and icons white over the wallpaper, and switches to
black only over a very light one, in light and dark mode alike. The Tahoe Shell keeps
the bar's ink in the app theme's family (dark text in light mode) and only adjusts its
brightness. This makes the top bar pick white or black from the wallpaper behind it
(the bar's own dark gradient included); the Dock and other glass are unchanged.
Patches the shared launcher module's source before it's built; safe to run again.

  patch-menubar-ink.py <macos-tahoe source tree>
"""
import sys
from pathlib import Path

MARK = "kali-looks: menu bar ink"
LAUNCHER = "src/offline/plasmoids/org.kde.mac.tahoe.liquid.taskmanager/launcher"

OLD_SAMPLES = '''private:
    struct Sample { QColor color; double lightness; };
    QList<Sample> m_samples;'''
NEW_SAMPLES = '''    // ''' + MARK + ''': average lightness of the backdrop under a label
    double meanLightness() const
    {
        if (m_samples.isEmpty()) return -1.;
        double sum = 0.;
        for (const auto &sample : m_samples) sum += sample.lightness;
        return sum / m_samples.size();
    }

private:
    struct Sample { QColor color; double lightness; };
    QList<Sample> m_samples;'''

OLD_FG = '''        return GlassInk::sample(GlassInk::label, bounds.center(), bounds.size() * .4, [&](QPointF p) {
            const int x = std::clamp(int(p.x() * m_grid.width() / m_window->width()), 0, m_grid.width() - 1);
            const int y = std::clamp(int(p.y() * m_grid.height() / m_window->height()), 0, m_grid.height() - 1);
            return GlassInk::composite(m_grid.pixelColor(x, y), fill);
        }).tone(base);'''
NEW_FG = '''        const auto samples = GlassInk::sample(GlassInk::label, bounds.center(), bounds.size() * .4, [&](QPointF p) {
            const int x = std::clamp(int(p.x() * m_grid.width() / m_window->width()), 0, m_grid.width() - 1);
            const int y = std::clamp(int(p.y() * m_grid.height() / m_window->height()), 0, m_grid.height() - 1);
            return GlassInk::composite(m_grid.pixelColor(x, y), fill);
        });
        // ''' + MARK + ''': the menu bar (top edge, no fill of its own) is white over
        // the wallpaper, black only over a very light one, whatever the app theme
        const double backdrop = samples.meanLightness();
        if (m_panel && m_panel->location() == Plasma::Types::TopEdge && fill.alpha() == 0 && backdrop >= 0.)
            base = backdrop < .86 ? QColor(Qt::white) : QColor(0x1d, 0x1d, 0x1f);
        return samples.tone(base);'''


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    src = Path(sys.argv[1]) / LAUNCHER
    ink, wall = src / "glassink.h", src / "panelwallpaper.cpp"
    a, b = ink.read_text(), wall.read_text()
    if MARK in a and MARK in b:
        print("menu bar ink: already patched")
        return
    if OLD_SAMPLES not in a or OLD_FG not in b:
        sys.exit("menu bar ink: the launcher module's source changed upstream; not patched")
    ink.write_text(a.replace(OLD_SAMPLES, NEW_SAMPLES, 1))
    wall.write_text(b.replace(OLD_FG, NEW_FG, 1))
    print("menu bar ink: patched (white over the wallpaper, black over very light ones)")


if __name__ == "__main__":
    main()
