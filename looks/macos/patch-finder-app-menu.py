#!/usr/bin/env python3
"""kali-looks: the bold "Finder" menu of the Tahoe menu bar opens, as on a Mac.

With no window in front, the menu bar's first menu reads Finder. On a Mac it opens:
About Finder; Settings...; Empty Trash...; Services; Hide Finder, Hide Others, Show All.
The Tahoe Shell's global menu opens nothing there (its app menu needs a window in
front). This fills it in: About shows Finder's About window, Settings opens Finder's
(Dolphin's) settings, Empty Trash asks first as macOS does, and Hide/Show work on
the open windows. Patches the global menu's source before it's built; safe to run again.

  patch-finder-app-menu.py <macos-tahoe source tree>
"""
import sys
from pathlib import Path

MARK = "kali-looks: Finder's own menu"

OLD = '''    auto* tasks = appModel->tasksModel();
    const QPersistentModelIndex activeTask(tasks->activeTask());
    if (!activeTask.isValid()) {
        return;
    }
'''

NEW = '''    auto* tasks = appModel->tasksModel();
    const QPersistentModelIndex activeTask(tasks->activeTask());
    if (!activeTask.isValid()) {
        // ''' + MARK + ''' (no window in front: About Finder, Settings, Empty Trash,
        // Services, Hide Finder, Hide Others, Show All)
        const QString finder = appModel->activeAppName();
        if (finder.isEmpty()) {
            return;
        }
        if (!m_windowMenu) {
            m_windowMenu = std::make_unique<ShellMenu>();
        }
        m_windowMenu->clear();
        const QString dolphinId = QStringLiteral("org.kde.dolphin");
        const QString dolphinDesktop = QStandardPaths::locate(QStandardPaths::GenericDataLocation,
                                                              QStringLiteral("applications/org.kde.dolphin.desktop"));
        // every window the Dock knows, its group's windows included
        auto forEachWindow = [tasks](const std::function<void(const QModelIndex &)> &fn) {
            for (int r = 0; r < tasks->rowCount(); ++r) {
                const QModelIndex idx = tasks->index(r, 0);
                const int children = tasks->rowCount(idx);
                if (children > 0) {
                    for (int c = 0; c < children; ++c) fn(tasks->index(c, 0, idx));
                } else {
                    fn(idx);
                }
            }
        };
        auto isFinder = [dolphinId](const QModelIndex &idx) {
            return idx.data(TaskManager::AbstractTasksModel::AppId).toString().startsWith(dolphinId);
        };
        auto setHidden = [tasks](const QModelIndex &idx, bool hidden) {
            if (idx.data(TaskManager::AbstractTasksModel::IsMinimized).toBool() != hidden
                && idx.data(TaskManager::AbstractTasksModel::IsMinimizable).toBool()) {
                tasks->requestToggleMinimized(idx);
            }
        };

        auto *about = m_windowMenu->addAction(i18n("About %1", QString(finder).replace(QLatin1Char('&'), QStringLiteral("&&"))));
        connect(about, &QAction::triggered, this, [this, finder, dolphinId, dolphinDesktop] {
            QVariantMap info;
            info.insert(QStringLiteral("name"), finder);
            info.insert(QStringLiteral("applicationId"), dolphinId);
            info.insert(QStringLiteral("executable"), QStandardPaths::findExecutable(QStringLiteral("dolphin")));
            QIcon icon = QIcon::fromTheme(QStringLiteral("system-file-manager"));
            if (!dolphinDesktop.isEmpty()) {
                KDesktopFile desktop(dolphinDesktop);
                info.insert(QStringLiteral("desktopFile"), dolphinDesktop);
                info.insert(QStringLiteral("description"), desktop.readGenericName());
                if (!desktop.readIcon().isEmpty()) icon = QIcon::fromTheme(desktop.readIcon());
            }
            info.insert(QStringLiteral("icon"), icon);
            QTimer::singleShot(0, this, [this, info] { Q_EMIT applicationAboutRequested(info); });
        });
        m_windowMenu->addSeparator();

        auto *settings = m_windowMenu->addAction(i18n("Settings…"));
        settings->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_Comma));
        connect(settings, &QAction::triggered, this, [] {
            // Finder's settings are Dolphin's "Configure Dolphin" window
            auto openSettings = [](auto &&self, int tries) -> void {
                const QStringList names = QDBusConnection::sessionBus().interface()->registeredServiceNames().value();
                for (const QString &name : names) {
                    if (name.startsWith(QLatin1String("org.kde.dolphin-"))) {
                        QDBusConnection::sessionBus().asyncCall(QDBusMessage::createMethodCall(
                            name, QStringLiteral("/dolphin/Dolphin_1/actions/options_configure"),
                            QStringLiteral("org.qtproject.Qt.QAction"), QStringLiteral("trigger")));
                        return;
                    }
                }
                if (tries == 0) {
                    QProcess::startDetached(QStringLiteral("dolphin"), {});
                }
                if (tries < 20) {
                    QTimer::singleShot(250, qApp, [self, tries] { self(self, tries + 1); });
                }
            };
            QTimer::singleShot(0, qApp, [openSettings] { openSettings(openSettings, 0); });
        });
        m_windowMenu->addSeparator();

        auto *emptyTrash = m_windowMenu->addAction(i18n("Empty Trash…"));
        emptyTrash->setShortcut(QKeySequence(Qt::CTRL | Qt::SHIFT | Qt::Key_Backspace));
        const QString trash = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/Trash/files");
        emptyTrash->setEnabled(!QDir(trash).isEmpty(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System));
        connect(emptyTrash, &QAction::triggered, this, [] {
            QTimer::singleShot(0, qApp, [] {
                QMessageBox box;
                box.setIcon(QMessageBox::Warning);
                box.setText(i18n("Are you sure you want to permanently erase the items in the Trash?"));
                box.setInformativeText(i18n("You can’t undo this action."));
                box.addButton(i18n("Cancel"), QMessageBox::RejectRole);
                auto *erase = box.addButton(i18n("Empty Trash"), QMessageBox::AcceptRole);
                box.setDefaultButton(erase);
                box.exec();
                if (box.clickedButton() == erase) {
                    QProcess::startDetached(QStringLiteral("ktrash6"), {QStringLiteral("--empty")});
                }
            });
        });
        m_windowMenu->addSeparator();

        auto *services = m_windowMenu->addMenu(i18n("Services"));
        services->addAction(i18n("No Services Apply"))->setEnabled(false);
        m_windowMenu->addSeparator();

        bool finderShown = false, othersShown = false, anyHidden = false;
        forEachWindow([&](const QModelIndex &idx) {
            const bool hidden = idx.data(TaskManager::AbstractTasksModel::IsMinimized).toBool();
            anyHidden = anyHidden || hidden;
            if (!hidden) (isFinder(idx) ? finderShown : othersShown) = true;
        });
        auto *hide = m_windowMenu->addAction(i18n("Hide %1", QString(finder).replace(QLatin1Char('&'), QStringLiteral("&&"))));
        hide->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_H));
        hide->setEnabled(finderShown);
        connect(hide, &QAction::triggered, this, [forEachWindow, isFinder, setHidden] {
            forEachWindow([&](const QModelIndex &idx) { if (isFinder(idx)) setHidden(idx, true); });
        });
        auto *hideOthers = m_windowMenu->addAction(i18n("Hide Others"));
        hideOthers->setShortcut(QKeySequence(Qt::CTRL | Qt::ALT | Qt::Key_H));
        hideOthers->setEnabled(othersShown);
        connect(hideOthers, &QAction::triggered, this, [forEachWindow, isFinder, setHidden] {
            forEachWindow([&](const QModelIndex &idx) { if (!isFinder(idx)) setHidden(idx, true); });
        });
        auto *showAll = m_windowMenu->addAction(i18n("Show All"));
        showAll->setEnabled(anyHidden);
        connect(showAll, &QAction::triggered, this, [forEachWindow, setHidden] {
            forEachWindow([&](const QModelIndex &idx) { setHidden(idx, false); });
        });

        showMenu(ctx, m_windowMenu.get(), WINDOW_MENU_INDEX);
        return;
    }
'''

INCLUDES = '#include <QDir>\n#include <QMessageBox>\n#include <QPushButton>\n#include <functional>\n'


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    src = Path(sys.argv[1]) / "src/offline/plasmoids/org.kde.mac.tahoe.liquid.globalmenu/appmenuapplet.cpp"
    s = src.read_text()
    if MARK in s:
        print("finder app menu: already patched")
        return
    if OLD not in s or '#include <QDBusMessage>\n' not in s:
        sys.exit("finder app menu: the global menu's source changed upstream; not patched")
    s = s.replace(OLD, NEW, 1)
    s = s.replace('#include <QDBusMessage>\n', '#include <QDBusMessage>\n' + INCLUDES, 1)
    src.write_text(s)
    print("finder app menu: patched (About Finder, Settings, Empty Trash, Services, Hide, Show All)")


if __name__ == "__main__":
    main()
