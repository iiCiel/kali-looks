// Windows XP layout for Plasma 6: one taskbar along the bottom of every screen, with a
// green start button, quick-launch icons and window buttons; tray and clock on the main screen.
// LOOKS_START_IMAGE is prepended by the `looks` command.

panels().forEach(function (p) { p.remove(); });

function taskbar(screen) {
    var bar = new Panel;
    bar.screen = screen;
    bar.location = "bottom";
    bar.height = Math.round(gridUnit * 1.9);
    bar.floating = false;
    bar.hiding = "none";
    bar.lengthMode = "fill";

    var start = bar.addWidget("org.kde.plasma.kicker");
    start.currentConfigGroup = ["General"];
    start.writeConfig("useCustomButtonImage", true);
    start.writeConfig("customButtonImage", LOOKS_START_IMAGE);
    start.writeConfig("showRecentApps", true);
    start.writeConfig("showRecentDocs", true);
    if (screen === 0) {
        start.currentConfigGroup = ["Shortcuts"];
        start.writeConfig("global", "Alt+F1");
    }

    var tasks = bar.addWidget("org.kde.plasma.taskmanager");
    tasks.currentConfigGroup = ["General"];
    tasks.writeConfig("launchers", [
        "preferred://browser",
        "preferred://filemanager",
        "applications:org.kde.konsole.desktop"
    ]);
    tasks.writeConfig("groupingStrategy", 0);
    tasks.writeConfig("showOnlyCurrentScreen", true);
    tasks.writeConfig("maxStripes", 1);

    if (screen === 0) {
        bar.addWidget("org.kde.plasma.systemtray");
    }
    var clock = bar.addWidget("org.kde.plasma.digitalclock");
    clock.currentConfigGroup = ["Appearance"];
    clock.writeConfig("showDate", false);
    clock.writeConfig("use24hFormat", 0);
    return bar;
}

for (var s = 0; s < screenCount; ++s) {
    taskbar(s);
}
