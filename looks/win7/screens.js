// kali-looks: every screen of the Windows 7 session gets the taskbar -- a copy of the
// main one (Start, pinned and open windows, notification area, clock, Show desktop) --
// and the Windows 7 wallpaper. Plasma desktop script, safe to run again. Prints
// "not ready" while Plasma is still placing its panels (run it again).
(function () {
  var all = panels(), bottom = [];
  for (var i = 0; i < all.length; i++)
    if (all[i].location == "bottom" && all[i].screen >= 0) bottom.push(all[i]);
  if (bottom.length == 0) { print("not ready"); return; }

  function find(panel, type) {
    var ws = panel.widgets();
    for (var k = 0; k < ws.length; k++) if (ws[k].type == type) return ws[k];
    return null;
  }
  var START = "io.gitgud.wackyideas.SevenStart";
  var main = null;
  for (var i = 0; i < bottom.length; i++)
    if (find(bottom[i], START) && (main === null || bottom[i].id < main.id)) main = bottom[i];
  if (main === null) { print("not ready"); return; }

  // One taskbar per screen (the main one stays where it is).
  var byScreen = {}, removed = 0;
  for (var i = 0; i < bottom.length; i++) {
    var p = bottom[i], s = p.screen;
    if (!(s in byScreen)) { byScreen[s] = p; continue; }
    var stay = (p === main || (byScreen[s] !== main && p.id < byScreen[s].id)) ? p : byScreen[s];
    var go = stay === p ? byScreen[s] : p;
    byScreen[s] = stay;
    go.remove();
    removed++;
  }

  function copyConfig(from, to, group) {
    from.currentConfigGroup = group;
    to.currentConfigGroup = group;
    var keys = from.configKeys;
    for (var k = 0; k < keys.length; k++) to.writeConfig(keys[k], from.readConfig(keys[k]));
    to.reloadConfig();
  }
  // the main taskbar's widgets, in their order
  main.currentConfigGroup = ["General"];
  var order = String(main.readConfig("AppletOrder") || "").split(";"), widgets = [];
  for (var k = 0; k < order.length; k++) {
    var w = order[k] ? main.widgetById(parseInt(order[k])) : null;
    if (w) widgets.push(w);
  }
  if (widgets.length == 0) widgets = main.widgets();

  var added = 0;
  for (var s = 0; s < screenCount; s++) {
    if (s in byScreen) continue;
    var panel = new Panel(main.type);
    panel.screen = s;
    panel.location = "bottom";
    panel.height = main.height;
    panel.hiding = main.hiding;
    panel.lengthMode = main.lengthMode;
    for (var k = 0; k < widgets.length; k++) {
      var w = panel.addWidget(widgets[k].type);
      if (w) copyConfig(widgets[k], w, ["General"]);
    }
    byScreen[s] = panel;
    added++;
  }

  // Wallpaper: screens without one of their own get the main screen's.
  var ds = desktops(), img = "", fill = "", g = ["Wallpaper", "org.kde.image", "General"];
  for (var d = 0; d < ds.length; d++)
    if (ds[d].screen == main.screen && ds[d].wallpaperPlugin == "org.kde.image") {
      ds[d].currentConfigGroup = g; img = ds[d].readConfig("Image"); fill = ds[d].readConfig("FillMode");
    }
  var filled = 0;
  if (img != "") for (var e = 0; e < ds.length; e++) {
    var dd = ds[e];
    if (dd.wallpaperPlugin != "org.kde.image") continue;
    dd.currentConfigGroup = g;
    var cur = dd.readConfig("Image");
    if (cur == "" || cur.indexOf("/usr/share/wallpapers/") >= 0) {
      dd.writeConfig("Image", img); dd.writeConfig("FillMode", fill); dd.reloadConfig(); filled++;
    }
  }
  print("taskbars added: " + added + ", extra taskbars removed: " + removed + ", wallpapers set: " + filled);
})();
