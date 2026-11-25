// macOS layout for Plasma 6: a menu bar on every screen, and a dock.
// LOOKS_DOCK ("plank" on X11, "panel" on Wayland) is prepended by the `looks` command.

// Start clean: remove existing panels and desktop widgets.
panels().forEach(function (p) { p.remove(); });

function menuBar(screen) {
    var bar = new Panel;
    bar.screen = screen;
    bar.location = "top";
    bar.height = Math.round(gridUnit * 1.6);
    bar.floating = false;
    bar.hiding = "none";
    bar.alignment = "left";

    // The Kali logo opens the app menu, where the Apple menu would be
    var menu = bar.addWidget("org.kde.plasma.kickoff");
    menu.currentConfigGroup = ["General"];
    menu.writeConfig("icon", "kali-menu");
    if (screen === 0) {
        menu.currentConfigGroup = ["Shortcuts"];
        menu.writeConfig("global", "Alt+F1");
    }

    // The focused app's name in bold ("Finder" on the desktop), then its File / Edit / View menus
    var title = bar.addWidget("org.kde.windowtitle");
    if (title) {
        title.currentConfigGroup = ["Appearance"];
        title.writeConfig("txt", "%a");
        title.writeConfig("altTxt", "Finder");
        title.writeConfig("txtSameFound", "%a");
        title.writeConfig("visible", false);   // the app icon (macOS shows only the name)
        title.writeConfig("isBold", true);
        title.writeConfig("fontSize", 13);       // pixels, like the menus next to it
        title.writeConfig("midSpace", 0);
        title.writeConfig("activityIcon", false);
        title.writeConfig("lastSpace", 6);
        title.currentConfigGroup = ["Behavior"];
        title.writeConfig("filterByScreen", true);
        title.writeConfig("showTooltip", false);
    }
    bar.addWidget("org.kde.plasma.appmenu");
    bar.addWidget("org.kde.plasma.panelspacer");

    // Status icons only on the main screen (the tray exists once per desktop)
    if (screen === 0) {
        bar.addWidget("org.kde.plasma.systemtray");
    }

    var clock = bar.addWidget("org.kde.plasma.digitalclock");
    clock.currentConfigGroup = ["Appearance"];
    clock.writeConfig("showDate", true);
    clock.writeConfig("dateDisplayFormat", "BesideTime");
    clock.writeConfig("dateFormat", "custom");
    clock.writeConfig("customDateFormat", "ddd MMM d");
    clock.writeConfig("use24hFormat", 0);
    clock.writeConfig("showSeconds", 0);
    return bar;
}

for (var s = 0; s < screenCount; ++s) {
    menuBar(s);
}

// Wayland (no Plank): a floating, auto-hiding dock panel
if (typeof LOOKS_DOCK === "undefined" || LOOKS_DOCK === "panel") {
    var dock = new Panel;
    dock.screen = 0;
    dock.location = "bottom";
    dock.floating = true;
    dock.lengthMode = "fit";
    dock.hiding = "dodgewindows";
    dock.height = Math.round(gridUnit * 3.4);
    var tasks = dock.addWidget("org.kde.plasma.icontasks");
    tasks.currentConfigGroup = ["General"];
    tasks.writeConfig("launchers", [
        "preferred://filemanager",
        "applications:kali-looks-launchpad.desktop",
        "preferred://browser",
        "applications:org.kde.konsole.desktop",
        "applications:org.kde.kate.desktop",
        "applications:systemsettings.desktop"
    ]);
    tasks.writeConfig("showOnlyCurrentDesktop", false);
    tasks.writeConfig("groupingStrategy", 1);
    dock.addWidget("org.kde.plasma.marginsseparator");
    dock.addWidget("org.kde.plasma.trash");
}
