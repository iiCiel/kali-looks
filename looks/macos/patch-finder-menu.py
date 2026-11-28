#!/usr/bin/env python3
"""kali-looks: the Finder menu of the Tahoe menu bar, with all of Finder's menus.

On a Mac, with no window in front the menu bar reads Finder, File, Edit, View, Go,
Window, Help. The Tahoe Shell's global menu shows File, Go and Help only. This adds
Edit, View and Window (items that can't act on the desktop are greyed out, as macOS
greys what's unavailable) and fills in File and Go. Patches the global menu's source
before it's built; safe to run again.

  patch-finder-menu.py <macos-tahoe source tree>
"""
import sys
from pathlib import Path

MARK = "kali-looks: Finder's full menu"

OLD = '''        auto *file = m_finderMenu->addMenu(i18n("&File"));
        auto *window = file->addAction(i18n("New Finder Window"));
        window->setShortcut(QKeySequence::New);
        connect(window, &QAction::triggered, this, [folder] {
            openFinderLocation(folder(QStandardPaths::HomeLocation), true);
        });
        auto *go = m_finderMenu->addMenu(i18n("&Go"));
        const QList<std::pair<QString, QUrl>> places = {'''

NEW = '''        // ''' + MARK + ''' (Finder, File, Edit, View, Go, Window, Help)
        auto unavailable = [](QMenu *menu, const QString &label, const QKeySequence &keys = {}) {
            auto *action = menu->addAction(label);
            if (!keys.isEmpty()) action->setShortcut(keys);
            action->setEnabled(false);
            return action;
        };
        auto *file = m_finderMenu->addMenu(i18n("&File"));
        auto *window = file->addAction(i18n("New Finder Window"));
        window->setShortcut(QKeySequence::New);
        connect(window, &QAction::triggered, this, [folder] {
            openFinderLocation(folder(QStandardPaths::HomeLocation), true);
        });
        auto *newFolder = file->addAction(i18n("New Folder"));
        newFolder->setShortcut(QKeySequence(Qt::CTRL | Qt::SHIFT | Qt::Key_N));
        connect(newFolder, &QAction::triggered, this, [folder] {
            const QString desktop = folder(QStandardPaths::DesktopLocation).toLocalFile();
            QString name = desktop + QStringLiteral("/untitled folder");
            for (int n = 2; QFileInfo::exists(name); ++n)
                name = desktop + QStringLiteral("/untitled folder %1").arg(n);
            QDir().mkpath(name);
        });
        unavailable(file, i18n("New Tab"), QKeySequence(Qt::CTRL | Qt::Key_T));
        file->addSeparator();
        unavailable(file, i18n("Open"), QKeySequence(Qt::CTRL | Qt::Key_O));
        unavailable(file, i18n("Close Window"), QKeySequence(Qt::CTRL | Qt::Key_W));
        file->addSeparator();
        unavailable(file, i18n("Get Info"), QKeySequence(Qt::CTRL | Qt::Key_I));
        unavailable(file, i18n("Rename"));
        file->addSeparator();
        auto *find = file->addAction(i18n("Find"));
        find->setShortcut(QKeySequence::Find);
        connect(find, &QAction::triggered, this, [] {
            QProcess::startDetached(QStringLiteral("qdbus6"),
                {QStringLiteral("org.kde.krunner"), QStringLiteral("/App"), QStringLiteral("org.kde.krunner.App.display")});
        });
        auto *edit = m_finderMenu->addMenu(i18n("&Edit"));
        unavailable(edit, i18n("Undo"), QKeySequence::Undo);
        unavailable(edit, i18n("Redo"), QKeySequence::Redo);
        edit->addSeparator();
        unavailable(edit, i18n("Cut"), QKeySequence::Cut);
        unavailable(edit, i18n("Copy"), QKeySequence::Copy);
        unavailable(edit, i18n("Paste"), QKeySequence::Paste);
        unavailable(edit, i18n("Select All"), QKeySequence::SelectAll);
        edit->addSeparator();
        unavailable(edit, i18n("Show Clipboard"));
        auto *view = m_finderMenu->addMenu(i18n("&View"));
        unavailable(view, i18n("as Icons"), QKeySequence(Qt::CTRL | Qt::Key_1));
        unavailable(view, i18n("as List"), QKeySequence(Qt::CTRL | Qt::Key_2));
        unavailable(view, i18n("as Columns"), QKeySequence(Qt::CTRL | Qt::Key_3));
        unavailable(view, i18n("as Gallery"), QKeySequence(Qt::CTRL | Qt::Key_4));
        view->addSeparator();
        unavailable(view, i18n("Use Stacks"));
        unavailable(view, i18n("Clean Up"));
        view->addSeparator();
        unavailable(view, i18n("Show View Options"), QKeySequence(Qt::CTRL | Qt::Key_J));
        auto *go = m_finderMenu->addMenu(i18n("&Go"));
        unavailable(go, i18n("Back"), QKeySequence(Qt::CTRL | Qt::Key_BracketLeft));
        unavailable(go, i18n("Forward"), QKeySequence(Qt::CTRL | Qt::Key_BracketRight));
        go->addSeparator();
        const QList<std::pair<QString, QUrl>> places = {'''

OLD_HELP = '''        auto *help = m_finderMenu->addMenu(i18n("&Help"));'''
NEW_HELP = '''        auto *windows = m_finderMenu->addMenu(i18n("&Window"));
        unavailable(windows, i18n("Minimize"), QKeySequence(Qt::CTRL | Qt::Key_M));
        unavailable(windows, i18n("Zoom"));
        windows->addSeparator();
        unavailable(windows, i18n("Bring All to Front"));
        auto *help = m_finderMenu->addMenu(i18n("&Help"));'''

INCLUDES = '#include <QDir>\n#include <QFileInfo>\n'


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    src = Path(sys.argv[1]) / "src/offline/plasmoids/org.kde.mac.tahoe.liquid.globalmenu/appmenumodel.cpp"
    s = src.read_text()
    if MARK in s:
        print("finder menu: already patched")
        return
    if OLD not in s or OLD_HELP not in s:
        sys.exit("finder menu: the global menu's source changed upstream; not patched")
    s = s.replace(OLD, NEW, 1).replace(OLD_HELP, NEW_HELP, 1)
    s = s.replace('#include <QDesktopServices>\n', '#include <QDesktopServices>\n' + INCLUDES, 1)
    src.write_text(s)
    print("finder menu: patched (Finder, File, Edit, View, Go, Window, Help)")


if __name__ == "__main__":
    main()
