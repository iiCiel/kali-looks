// kali-looks: every screen of the XP session gets an XP taskbar and the XP wallpaper.
// Plasma desktop script (run with org.kde.PlasmaShell.evaluateScript); safe to run
// again: screens that already have a taskbar, or a wallpaper of their own, are left alone.
(function () {
  var all = panels();
  var main = null;
  for (var i = 0; i < all.length; i++) {
    var ws = all[i].widgets();
    for (var j = 0; j < ws.length; j++)
      if (ws[j].type == "fyi.hotsocket.xplasma.start" && (main === null || all[i].screen == 0)) main = all[i];
  }
  if (main === null) { print("no XP taskbar to copy"); return; }

  function find(panel, type) {
    var ws = panel.widgets();
    for (var k = 0; k < ws.length; k++) if (ws[k].type == type) return ws[k];
    return null;
  }
  function copyConfig(from, to, extra) {
    if (!from) return;
    from.currentConfigGroup = ["General"];
    to.currentConfigGroup = ["General"];
    var keys = from.configKeys;
    for (var k = 0; k < keys.length; k++) to.writeConfig(keys[k], from.readConfig(keys[k]));
    for (var key in (extra || {})) to.writeConfig(key, extra[key]);
    to.reloadConfig();
  }

  var added = 0;
  for (var s = 0; s < screenCount; s++) {
    var has = false;
    for (var p = 0; p < all.length; p++)
      if (all[p].screen == s && all[p].location == "bottom") has = true;
    if (has) continue;
    var panel = new Panel("org.kde.panel");
    panel.screen = s;
    panel.location = "bottom";
    panel.height = main.height;
    panel.hiding = main.hiding;
    panel.floating = false;
    panel.lengthMode = "fill";
    var start = panel.addWidget("fyi.hotsocket.xplasma.start");
    copyConfig(find(main, "fyi.hotsocket.xplasma.start"), start);
    var tasks = panel.addWidget("org.kde.plasma.taskmanager");
    copyConfig(find(main, "org.kde.plasma.taskmanager"), tasks, { showOnlyCurrentScreen: true });
    var clock = panel.addWidget("fyi.hotsocket.xplasma.clock");
    copyConfig(find(main, "fyi.hotsocket.xplasma.clock"), clock);
    added++;
  }
  // The main taskbar lists only its own screen's windows too, as each screen has one now.
  if (screenCount > 1) {
    var mt = find(main, "org.kde.plasma.taskmanager");
    if (mt) { mt.currentConfigGroup = ["General"]; mt.writeConfig("showOnlyCurrentScreen", true); mt.reloadConfig(); }
  }

  // Wallpaper: screens without one of their own get the main screen's.
  var ds = desktops(), img = "", g = ["Wallpaper", "org.kde.image", "General"];
  for (var d = 0; d < ds.length; d++)
    if (ds[d].screen == main.screen && ds[d].wallpaperPlugin == "org.kde.image") { ds[d].currentConfigGroup = g; img = ds[d].readConfig("Image"); }
  var filled = 0;
  if (img != "") for (var e = 0; e < ds.length; e++) {
    var dd = ds[e];
    if (dd.wallpaperPlugin != "org.kde.image") continue;
    dd.currentConfigGroup = g;
    var cur = dd.readConfig("Image");
    if (cur == "" || cur.indexOf("/usr/share/wallpapers/") >= 0) { dd.writeConfig("Image", img); filled++; }
  }
  print("taskbars added: " + added + ", wallpapers set: " + filled);
})();
