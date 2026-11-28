#!/usr/bin/env python3
"""kali-looks: running apps stay in the Dock, with a dot and Quit, as on a Mac.

Plasma's task manager only knows about windows. An app closed to the menu bar
(Discord, Steam, ...) lost its Dock icon, so there was nothing to right-click and
no way to see it was still running. On a Mac every running app keeps its Dock icon
and a dot, windows or not, and its menu has Quit.

`looks dock-apps list --dock` names the running apps (Plasma starts each app in its
own systemd unit). The Dock polls it every 2 s: running apps get a dot; one that
isn't pinned gets a Dock icon until it quits, never saved as a pin; every running
app's menu gets Quit, which ends the whole app (`looks dock-apps quit`). "Pin to
Task Manager" on such an icon keeps it for good.

  patch-dock-running.py <macos-tahoe source tree | installed plasmoid folder>
Safe to run again.
"""
import sys
from pathlib import Path

PLASMOID = "org.kde.mac.tahoe.liquid.taskmanager"
SRC_UI = f"src/offline/plasmoids/{PLASMOID}/contents/ui"
MARK = "kali-looks: running apps"

MAIN_BLOCK = '''    // kali-looks: running apps stay in the Dock, as on a Mac. Plasma only lists windows, so
    // an app closed to the menu bar (Discord, Steam...) vanished with no way to quit it.
    // `looks dock-apps` names the running apps: each keeps a dot and gets Quit, and one
    // that isn't pinned keeps a Dock icon until it quits (never saved as a pin).
    property var runningAppIds: []
    property var backgroundPins: []
    readonly property string dockAppsProgram: "sh -c 'exec \\"$HOME/.local/bin/looks\\" dock-apps \\"$@\\"' dock-apps "

    function appIdOf(url: var): string {
        return String(url || "").split("\\n").pop().split(/[/:]/).pop().replace(/\\.desktop$/, "");
    }
    function isRunningApp(url: var): bool {
        const id = appIdOf(url);
        return id !== "" && runningAppIds.indexOf(id) >= 0;
    }
    function isBackgroundPin(url: var): bool {
        return backgroundPins.indexOf("applications:" + appIdOf(url) + ".desktop") >= 0;
    }
    function keepInDock(url: var): void {
        const pin = "applications:" + appIdOf(url) + ".desktop";
        backgroundPins = backgroundPins.filter(p => p !== pin);
        Plasmoid.configuration.launchers = tasksModel.launcherList.filter(p => backgroundPins.indexOf(p) < 0);
    }
    function quitApp(url: var): void {
        const id = appIdOf(url);
        if (/^[A-Za-z0-9._-]+$/.test(id)) {
            dockApps.connectSource(dockAppsProgram + "quit " + id);
        }
    }
    function updateBackgroundPins(): void {
        if (!iconsOnly) {
            return;
        }
        const pinned = Plasmoid.configuration.launchers.map(appIdOf);
        const want = runningAppIds.filter(id => pinned.indexOf(id) < 0)
            .map(id => "applications:" + id + ".desktop");
        for (const pin of backgroundPins.filter(p => want.indexOf(p) < 0)) {
            backgroundPins = backgroundPins.filter(p => p !== pin);
            if (pinned.indexOf(appIdOf(pin)) < 0) {
                tasksModel.requestRemoveLauncher(pin);
            }
        }
        for (const pin of want.filter(p => backgroundPins.indexOf(p) < 0)) {
            backgroundPins = backgroundPins.concat([pin]); // first, so it isn't saved as a pin
            tasksModel.requestAddLauncher(pin);
        }
    }

    P5Support.DataSource {
        id: dockApps
        engine: "executable"
        readonly property string list: tasks.dockAppsProgram + "list --dock"
        connectedSources: [list]
        interval: 2000
        onNewData: (source, data) => {
            if (source !== list) {
                disconnectSource(source);
                return;
            }
            if (Number(data["exit code"]) !== 0) {
                return;
            }
            const ids = String(data["stdout"]).split("\\n").filter(s => s !== "");
            if (ids.join(" ") !== tasks.runningAppIds.join(" ")) {
                tasks.runningAppIds = ids;
            }
            tasks.updateBackgroundPins();
        }
    }

'''

QUIT_ITEM = '''
    // kali-looks: running apps get Quit, as in a Mac Dock: the whole app, windows or not
    PlasmaExtras.MenuItem {
        id: quitAppItem
        visible: menu.visualParent !== null
            && tasks.isRunningApp(menu.get(TaskManager.AbstractTasksModel.LauncherUrlWithoutIcon))
        text: i18ndc("plasma_applet_org.kde.plasma.taskmanager", "Quit media player app", "Quit")
        icon: "application-exit"
        onClicked: tasks.quitApp(menu.get(TaskManager.AbstractTasksModel.LauncherUrlWithoutIcon))
    }
'''

EDITS = [
    ("main.qml",  # the running-app state, before the layout code
     "    // For making a bottom to top layout since qml flow can't do that.\n",
     MAIN_BLOCK + "    // For making a bottom to top layout since qml flow can't do that.\n"),
    ("main.qml",  # icons for running apps are never saved as pins
     "        onLauncherListChanged: {\n"
     "            Plasmoid.configuration.launchers = launcherList;\n"
     "        }\n\n"
     "        function syncConfiguredLaunchers() {\n"
     "            const pins = Plasmoid.configuration.launchers;\n"
     "            launcherList = tasks.iconsOnly ? pins.map(DockRoles.preferredFileManagerPin) : pins;\n"
     "        }\n",
     "        onLauncherListChanged: {\n"
     "            // kali-looks: running apps' Dock icons aren't pins\n"
     "            Plasmoid.configuration.launchers = launcherList.filter(p => tasks.backgroundPins.indexOf(p) < 0);\n"
     "        }\n\n"
     "        function syncConfiguredLaunchers() {\n"
     "            const pins = Plasmoid.configuration.launchers;\n"
     "            const kept = tasks.iconsOnly ? pins.map(DockRoles.preferredFileManagerPin) : pins;\n"
     "            launcherList = kept.concat(tasks.backgroundPins.filter(p => kept.indexOf(p) < 0));\n"
     "        }\n"),
    ("Task.qml",  # a running app with no window still gets its dot
     "            name: \"launcher\"\n"
     "            when: task.model.IsLauncher\n",
     "            name: \"launcher\"\n"
     "            // kali-looks: running apps keep their dot with no window open\n"
     "            when: task.model.IsLauncher && !task.tasksRoot.isRunningApp(task.model.LauncherUrlWithoutIcon)\n"),
    ("ContextMenu.qml",  # "Pin" on a running app's icon keeps it for good
     "        visible: menu.visualParent\n"
     "            && !menu.get(TaskManager.AbstractTasksModel.IsLauncher)\n"
     "            && !menu.get(TaskManager.AbstractTasksModel.IsStartup)\n"
     "            && Plasmoid.immutability !== PlasmaCore.Types.SystemImmutable\n"
     "            && (activityInfo.numberOfRunningActivities < 2)\n"
     "            && !doesBelongToCurrentActivity()\n",
     "        // kali-looks: running apps' Dock icons can be pinned for good\n"
     "        readonly property bool backgroundPin: menu.visualParent !== null\n"
     "            && tasks.isBackgroundPin(menu.get(TaskManager.AbstractTasksModel.LauncherUrlWithoutIcon))\n"
     "        visible: menu.visualParent\n"
     "            && (!menu.get(TaskManager.AbstractTasksModel.IsLauncher) || backgroundPin)\n"
     "            && !menu.get(TaskManager.AbstractTasksModel.IsStartup)\n"
     "            && Plasmoid.immutability !== PlasmaCore.Types.SystemImmutable\n"
     "            && (activityInfo.numberOfRunningActivities < 2)\n"
     "            && (!doesBelongToCurrentActivity() || backgroundPin)\n"),
    ("ContextMenu.qml",
     "        onClicked: {\n"
     "            tasksModel.requestAddLauncher(menu.get(TaskManager.AbstractTasksModel.LauncherUrl));\n"
     "        }\n",
     "        onClicked: {\n"
     "            if (backgroundPin) {\n"
     "                tasks.keepInDock(menu.get(TaskManager.AbstractTasksModel.LauncherUrlWithoutIcon));\n"
     "            } else {\n"
     "                tasksModel.requestAddLauncher(menu.get(TaskManager.AbstractTasksModel.LauncherUrl));\n"
     "            }\n"
     "        }\n"),
    ("ContextMenu.qml",  # Quit, last, as on a Mac
     "            tasksModel.requestClose(menu.modelIndex);\n"
     "        }\n"
     "    }\n"
     "}\n",
     "            tasksModel.requestClose(menu.modelIndex);\n"
     "        }\n"
     "    }\n" + QUIT_ITEM + "}\n"),
]


def ui_dir(root: Path) -> Path:
    for d in (root / SRC_UI, root / "contents/ui"):
        if (d / "main.qml").is_file():
            return d
    sys.exit(f"dock running apps: no {PLASMOID} under {root}")


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    ui = ui_dir(Path(sys.argv[1]).expanduser())
    files = {name: (ui / name).read_text() for name in {e[0] for e in EDITS}}
    if all(MARK in files[n] or "kali-looks: running apps" in files[n] for n in files):
        print("dock running apps: already patched")
        return
    for name, old, new in EDITS:
        if files[name].count(old) != 1:
            sys.exit(f"dock running apps: {name} changed upstream; not patched")
        files[name] = files[name].replace(old, new, 1)
    for name, text in files.items():
        (ui / name).write_text(text)
    print("dock running apps: patched (dot, Dock icon and Quit for running apps)")


if __name__ == "__main__":
    main()
