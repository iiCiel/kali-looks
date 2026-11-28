// kali-looks: on a Mac every screen has the menu bar (the Dock stays on the main one).
// Each screen of the Tahoe session that has no menu bar gets an exact copy of the main
// one: same items in the same order, same settings. Plasma desktop script
// (org.kde.PlasmaShell.evaluateScript), safe to run again. Prints "not ready" while
// Plasma is still placing its panels (run it again), and "added: <panel ids>" otherwise.
(function () {
  var MENU = "org.kde.mac.tahoe.liquid.globalmenu";
  // (A bar on screen -1 belongs to a screen that isn't connected now: left alone.)
  var all = panels(), bars = [];
  for (var i = 0; i < all.length; i++) {
    var p = all[i];
    if (p.location != "top" || p.screen < 0) continue;
    var ws = p.widgets();
    for (var k = 0; k < ws.length; k++) if (ws[k].type == MENU) { bars.push(p); break; }
  }
  if (bars.length == 0) { print("not ready"); return; }
  var main = bars[0];
  for (var i = 1; i < bars.length; i++)
    if (bars[i].screen < main.screen || (bars[i].screen == main.screen && bars[i].id < main.id)) main = bars[i];

  var on = {};
  for (var i = 0; i < bars.length; i++) on[bars[i].screen] = true;

  // every key of every group below <group>, as it is on the main bar
  function copyGroup(from, to, group, ids) {
    // the tray's own widgets live in its hidden containment: the copy has its own
    if (group.length == 1 && group[0] == "Applets") return;
    from.currentConfigGroup = group;
    var keys = from.configKeys, subs = from.configGroups;
    var vals = {};
    for (var k = 0; k < keys.length; k++) vals[keys[k]] = from.readConfig(keys[k]);
    to.currentConfigGroup = group;
    for (var key in vals) {
      // the tray's own hidden containment: the copy has made its own
      if (key == "SystrayContainmentId") continue;
      var v = vals[key];
      // Panel Colorizer lists the bar's widgets by id: point it at the copies
      if (key == "panelWidgets") v = String(v).replace(/"id":(\d+)/g, function (m, id) {
        return '"id":' + (ids[id] !== undefined ? ids[id] : id); });
      to.writeConfig(key, v);
    }
    for (var s = 0; s < subs.length; s++) copyGroup(from, to, group.concat([subs[s]]), ids);
  }
  function widgetsInOrder(panel) {
    var ws = panel.widgets(), byId = {};
    for (var k = 0; k < ws.length; k++) byId[ws[k].id] = ws[k];
    panel.currentConfigGroup = ["General"];
    var order = String(panel.readConfig("AppletOrder", "")).split(";"), out = [];
    for (var k = 0; k < order.length; k++) if (byId[order[k]]) { out.push(byId[order[k]]); delete byId[order[k]]; }
    for (var id in byId) out.push(byId[id]);
    return out;
  }

  var added = [];
  for (var s = 0; s < screenCount; s++) {
    if (on[s]) continue;
    var bar = new Panel("org.kde.panel");
    bar.screen = s;
    bar.location = "top";
    bar.lengthMode = main.lengthMode;
    bar.hiding = main.hiding;
    bar.floating = main.floating;
    bar.height = main.height;
    bar.opacity = main.opacity;
    var from = widgetsInOrder(main), to = [], ids = {};
    for (var k = 0; k < from.length; k++) {
      to.push(bar.addWidget(from[k].type));
      if (to[k]) ids[from[k].id] = to[k].id;
    }
    for (var k = 0; k < from.length; k++) {
      if (!to[k]) continue;
      from[k].currentConfigGroup = [];
      var top = from[k].configGroups;
      for (var g = 0; g < top.length; g++) copyGroup(from[k], to[k], [top[g]], ids);
      to[k].reloadConfig();
    }
    on[s] = true;
    added.push(bar.id);
  }
  print("main: " + main.id + ", added: " + added.join(","));
})();
