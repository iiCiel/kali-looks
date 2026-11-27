// kali-looks: every screen of the XP session gets one XP taskbar -- Start, every open
// window, the notification area (volume, network, battery...) and the clock -- and the
// XP wallpaper. Plasma desktop script (org.kde.PlasmaShell.evaluateScript), safe to run
// again. Prints "not ready" while Plasma is still placing its panels (run it again).
(function () {
  // (A taskbar on screen -1 belongs to a screen that isn't connected now: left alone.)
  var all = panels();
  var bottom = [];
  for (var i = 0; i < all.length; i++)
    if (all[i].location == "bottom" && all[i].screen >= 0) bottom.push(all[i]);
  if (bottom.length == 0) { print("not ready"); return; }

  function find(panel, type) {
    var ws = panel.widgets();
    for (var k = 0; k < ws.length; k++) if (ws[k].type == type) return ws[k];
    return null;
  }
  function isXp(panel) { return find(panel, "fyi.hotsocket.xplasma.start") !== null; }
  var main = null;
  for (var i = 0; i < bottom.length; i++)
    if (isXp(bottom[i]) && find(bottom[i], "org.kde.plasma.systemtray") &&
        (main === null || find(bottom[i], "org.kde.plasma.quicklaunch")))
      main = bottom[i];
  if (main === null) { print("not ready"); return; }

  var keep = function (a, b) { // which of two taskbars on one screen stays
    if (a === main || b === main) return a === main ? a : b;
    var ta = find(a, "org.kde.plasma.systemtray") !== null, tb = find(b, "org.kde.plasma.systemtray") !== null;
    if (ta != tb) return ta ? a : b;
    return a.id < b.id ? a : b;
  };
  // One taskbar per screen.
  var byScreen = {}, removed = 0;
  for (var i = 0; i < bottom.length; i++) {
    var p = bottom[i], s = p.screen;
    if (!(s in byScreen)) { byScreen[s] = p; continue; }
    var stay = keep(byScreen[s], p), go = stay === p ? byScreen[s] : p;
    byScreen[s] = stay;
    go.remove();
    removed++;
  }

  function copyConfig(from, to, group, extra, skip) {
    if (!from) return;
    from.currentConfigGroup = group;
    to.currentConfigGroup = group;
    var keys = from.configKeys;
    for (var k = 0; k < keys.length; k++) {
      var v = from.readConfig(keys[k]);
      if (skip) v = skip(keys[k], v);
      to.writeConfig(keys[k], v);
    }
    for (var key in (extra || {})) to.writeConfig(key, extra[key]);
    to.reloadConfig();
  }
  // KDE's own notification-area items (XPlasma themes them), not Windows 7's.
  var kdeOnly = function (key, value) {
    if (key == "shownItems") { // volume, network and battery always in sight
      var shown = String(value).split(",").filter(function (x) { return x; });
      ["org.kde.plasma.volume", "org.kde.plasma.networkmanagement", "org.kde.plasma.battery"].forEach(function (x) {
        if (shown.indexOf(x) < 0) shown.push(x);
      });
      return shown.join(",");
    }
    if (key != "extraItems") return value;
    var items = String(value).split(","), out = [];
    for (var k = 0; k < items.length; k++)
      if (items[k] && items[k].indexOf("io.gitgud.wackyideas.") != 0) out.push(items[k]);
    return out.join(",");
  };

  var added = 0;
  for (var s = 0; s < screenCount; s++) {
    if (s in byScreen) continue;
    var panel = new Panel("org.kde.panel");
    panel.screen = s;
    panel.location = "bottom";
    panel.height = main.height;
    panel.hiding = main.hiding;
    panel.floating = false;
    panel.lengthMode = "fill";
    copyConfig(find(main, "fyi.hotsocket.xplasma.start"), panel.addWidget("fyi.hotsocket.xplasma.start"), ["General"]);
    copyConfig(find(main, "org.kde.plasma.taskmanager"), panel.addWidget("org.kde.plasma.taskmanager"), ["General"],
               { showOnlyCurrentScreen: false });
    copyConfig(find(main, "org.kde.plasma.systemtray"), panel.addWidget("org.kde.plasma.systemtray"), ["General"], null, kdeOnly);
    copyConfig(find(main, "fyi.hotsocket.xplasma.clock"), panel.addWidget("fyi.hotsocket.xplasma.clock"), ["General"]);
    byScreen[s] = panel;
    added++;
  }
  // Every taskbar lists every window, so they all show the same.
  for (var s in byScreen) {
    var t = find(byScreen[s], "org.kde.plasma.taskmanager");
    if (t) {
      t.currentConfigGroup = ["General"];
      if (String(t.readConfig("showOnlyCurrentScreen")) != "false") { t.writeConfig("showOnlyCurrentScreen", false); t.reloadConfig(); }
    }
  }

  // Wallpaper: screens without one of their own get the main screen's.
  var ds = desktops(), img = "", g = ["Wallpaper", "org.kde.image", "General"];
  for (var d = 0; d < ds.length; d++)
    if (ds[d].screen == main.screen && ds[d].wallpaperPlugin == "org.kde.image") {
      ds[d].currentConfigGroup = g; img = ds[d].readConfig("Image");
      var fill = ds[d].readConfig("FillMode"), color = ds[d].readConfig("Color");
    }
  var filled = 0;
  if (img != "") for (var e = 0; e < ds.length; e++) {
    var dd = ds[e];
    if (dd.wallpaperPlugin != "org.kde.image") continue;
    dd.currentConfigGroup = g;
    var cur = dd.readConfig("Image");
    if (cur == "" || cur.indexOf("/usr/share/wallpapers/") >= 0 || cur.indexOf("kali-looks/wallpapers/") >= 0) {
      dd.writeConfig("Image", img); dd.writeConfig("FillMode", fill); dd.writeConfig("Color", color); dd.reloadConfig(); filled++;
    }
  }
  print("taskbars added: " + added + ", extra taskbars removed: " + removed + ", wallpapers set: " + filled);
})();
