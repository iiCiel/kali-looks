#!/usr/bin/env python3
"""kali-looks: finishing touches that make XPlasma Plus match Windows XP.

Usage: xp-finish.py CONFIG_DIR [XPLASMA_SRC]  (files only; run while Plasma isn't running)
       xp-finish.py --live                    (things that need the running session)

Every change is idempotent (marked "kali-looks") and only touches the XP look:
XPlasma's own widgets in ~/.local/share/plasma and the XP look's config folder.
"""
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
HERE = Path(__file__).resolve().parent
PLASMOIDS = HOME / ".local/share/plasma/plasmoids"
AVATARS = HOME / ".local/share/plasma/avatars/windows-xp"
APPS = HOME / ".local/share/applications"
DATA = HOME / ".local/share/kali-looks"
MARK = "kali-looks"


def log(msg):
    print(f"xp-finish: {msg}")


def patch(path, edits):
    """Apply (old, new) replacements once. Skips a file already patched."""
    if not path.exists():
        log(f"missing {path}, skipped")
        return False
    text = path.read_text()
    if f"{MARK}: xp-finish" in text:
        return False
    for old, new in edits:
        if old not in text:
            log(f"{path.name}: expected code not found, left as it is")
            return False
        text = text.replace(old, new, 1)
    text = text.replace("\n", f"\n// {MARK}: xp-finish\n", 1)
    path.write_text(text)
    log(f"patched {path.name}")
    return True


# ---- desktop right-click menu: XP's items, in XP's order ---------------------------

def desktop_menu():
    f = PLASMOIDS / "org.kde.desktopcontainment/contents/ui/FolderViewLayer.qml"
    paste_cmd = f"python3 '{HERE / 'paste-shortcut.py'}'"
    patch(f, [
        # labels and visibility, refreshed every time the menu opens
        ("""    function updateContextualActions() {
        folderView.model.updateActions();
""",
         """    function updateContextualActions() {
        folderView.model.updateActions();
        if (Plasmoid.isContainment) xpMenuText();
"""),
        ("""    function cancelRename() {""",
         """    // kali-looks: Windows XP's words for the desktop menu.
    function xpMenuText() {
        const m = folderView.model;
        const set = (name, text) => { const a = m.action(name); if (a) a.text = text; return a; };
        set("refresh", "R&efresh");
        set("newMenu", "Ne&w");
        const paste = set("paste", "&Paste");
        if (paste) paste.shortcutVisibleInContextMenu = false;
        const refresh = m.action("refresh");
        if (refresh) refresh.shortcutVisibleInContextMenu = false;
        const undo = m.action("undo");
        if (undo) {
            // KIO says "Und&o: Rename"; XP says "Undo Rename", and only when there is one.
            undo.text = undo.text.replace(/^Und&?o:?\\s*/, "&Undo ").replace(/\\s+$/, "");
            undo.visible = undo.enabled;
        }
        xpPasteShortcut.enabled = paste ? paste.enabled : false;
    }

    function cancelRename() {"""),
        ("""    PlasmaCore.Action {
        id: actionSeparator
        isSeparator: true
    }
""",
         f"""    PlasmaCore.Action {{
        id: actionSeparator
        isSeparator: true
    }}
    PlasmaCore.Action {{ id: xpSep1; isSeparator: true }}
    PlasmaCore.Action {{ id: xpSep2; isSeparator: true }}
    PlasmaCore.Action {{ id: xpSep3; isSeparator: true }}
    PlasmaCore.Action {{
        id: xpPasteShortcut
        text: "Paste &Shortcut"
        onTriggered: xpLauncher.connectSource("{paste_cmd} '" + folderView.url + "'")
    }}
"""),
        ("""        for (let i = 0, len = sharedActions.length; i < len; i++) {
            const actionName = sharedActions[i];
            const modelAction = folderView.model.action(actionName);
            Plasmoid.contextualActions.push(modelAction)
            if (actionName === "emptyTrash") {
                Plasmoid.contextualActions.push(viewPropertiesAction)
            }
        }

        Plasmoid.contextualActions.push(actionSeparator);
        if (isContainment)
            Plasmoid.contextualActions.push(xpPropertiesAction);   // XPlasma
""",
         """        if (Plasmoid.isContainment) {
            // kali-looks: XP's desktop menu -- Arrange Icons By, Refresh | Paste,
            // Paste Shortcut, Undo | New | Properties
            const m = folderView.model;
            viewPropertiesAction.text = "Arrange &Icons By";
            viewPropertiesAction.icon.name = "";
            xpPropertiesAction.text = "P&roperties";
            xpPropertiesAction.icon.name = "";
            for (const a of [viewPropertiesAction, m.action("refresh"), xpSep1, m.action("paste"),
                             xpPasteShortcut, m.action("undo"), xpSep2, m.action("newMenu"), xpSep3,
                             xpPropertiesAction]) {
                if (a) Plasmoid.contextualActions.push(a);
            }
            xpMenuText();
        } else {
            for (let i = 0, len = sharedActions.length; i < len; i++) {
                const actionName = sharedActions[i];
                const modelAction = folderView.model.action(actionName);
                Plasmoid.contextualActions.push(modelAction)
                if (actionName === "emptyTrash") {
                    Plasmoid.contextualActions.push(viewPropertiesAction)
                }
            }
            Plasmoid.contextualActions.push(actionSeparator);
        }
"""),
    ])


# ---- Start menu: XP's places, pinned Internet/E-mail, an XP account picture ---------

def start_menu():
    f = PLASMOIDS / "fyi.hotsocket.xplasma.start/contents/ui/XpBackend.qml"
    picture = AVATARS / "xp-chess.png"
    patch(f, [
        ("""    readonly property url userPicture: user.faceIconUrl.toString() !== "" ? user.faceIconUrl
                                                                           : (launcher.themeData?.userPicture ?? "")""",
         f"""    // kali-looks: an XP account picture, as XP gave every account one
    readonly property url userPicture: "{picture.as_uri()}\""""),
        ("""        for (const entry of result) {
            entry.description = "";
        }
        recent = result;""",
         """        for (const entry of result) {
            entry.description = "";
        }
        // kali-looks: XP's pinned rows say what they are ("Internet", "E-mail")
        // with the program underneath; other pinned programs show just their name.
        for (const entry of pinned) {
            const kind = xpPinnedKind(entry);
            if (kind) { entry.description = entry.label; entry.label = kind; }
            else entry.description = "";
        }
        pinned = pinned.slice();
        recent = result;"""),
        ("""    function pathUrl(location) {""",
         """    function xpPinnedKind(entry) {
        const id = (entry.identity + " " + entry.url).toLowerCase();
        if (id.indexOf("preferred://browser") !== -1 || /firefox|chrom|brave|vivaldi|opera|edge|browser/.test(id)) return "Internet";
        if (id.indexOf("preferred://mail") !== -1 || /thunderbird|evolution|kmail|geary|claws|outlook|mail/.test(id)) return "E-mail";
        return "";
    }
    function pathUrl(location) {"""),
        ("""        [{label: launcher.xpExplorerEnabled ? "My Documents" : "Documents", """,
         """        [{label: "My Documents", """),
        ("""         {label: "Recent Files", icon""", """         {label: "My Recent Documents", icon"""),
        ("""         {label: "Pictures", icon""", """         {label: "My Pictures", icon"""),
        ("""         {label: "Music", icon""", """         {label: "My Music", icon"""),
        ("""         {label: launcher.xpExplorerEnabled ? "My Computer" : "File System", """,
         """         {label: "My Computer", """),
        ("""        [{label: launcher.xpControlPanelEnabled ? "Control Panel" : "System Settings", """,
         """        [{label: "Control Panel", """),
        ("""         {label: "Default Applications", icon""", """         {label: "Set Program Access and Defaults", icon"""),
        ("""         {label: "Printers", icon""", """         {label: "Printers and Faxes", icon"""),
        ("""        [{label: "Help Center", icon""", """        [{label: "Help and Support", icon"""),
        ("""         {label: "Run Command...", icon""", """         {label: "Run...", icon"""),
        ("""browseRequested(documents, "Recent Files", false)""",
         """browseRequested(documents, "My Recent Documents", false)"""),
    ])


def start_menu_width():
    # XP sized the Start menu to its longest entry ("Set Program Access and
    # Defaults" fits); XPlasma's theme fixes it at 380 px and cuts that one off.
    f = PLASMOIDS / "fyi.hotsocket.xplasma.start/contents/ui/XpFullRepresentation.qml"
    patch(f, [("implicitWidth: root.launcher.themeData.layout.width - frameLeft - frameRight",
               "implicitWidth: root.launcher.themeData.layout.width + 40 - frameLeft - frameRight  // kali-looks")])
    patch(PLASMOIDS / "fyi.hotsocket.xplasma.start/contents/ui/StartMenu.qml",
          [("    width: metrics.width\n", "    width: metrics.width + 40  // kali-looks: room for XP's longest entry\n")])


def programs_menus():
    # XP's All Programs menus have no title row, and grow to the screen's height
    # instead of scrolling after 17 entries.
    patch(PLASMOIDS / "fyi.hotsocket.xplasma.start/contents/ui/XpProgramsPopup.qml", [
        ("height: Math.min(420, Math.max(54, entries.count * 24 + 30))",
         "height: Math.min(900, Math.max(30, entries.count * 24 + 7))  // kali-looks"),
        ("""            x: 10; y: 6; width: parent.width - 20
            text: popup.title""",
         """            x: 10; y: 6; width: parent.width - 20
            visible: false  // kali-looks: XP has no title here
            text: popup.title"""),
        ("x: 6; y: 26; width: parent.width - 12; height: parent.height - y - 4",
         "x: 3; y: 3; width: parent.width - 6; height: parent.height - y - 4"),
    ])


def user_pictures(src):
    if (AVATARS / "xp-chess.png").exists() or not src:
        return
    pics = Path(src) / "payload/assets/user-pictures"
    if pics.is_dir():
        shutil.copytree(pics, AVATARS, dirs_exist_ok=True)
        log("XP account pictures added")


# ---- config of the XP session (written while Plasma isn't running) ------------------

def ini_set(path, group, values):
    """Set keys in one [group] of a KDE ini file, keeping everything else."""
    text = path.read_text() if path.exists() else ""
    lines = text.splitlines()
    header = "[" + "][".join(group) + "]"
    try:
        start = lines.index(header)
    except ValueError:
        lines += ["", header]
        start = len(lines) - 1
    end = start + 1
    while end < len(lines) and not lines[end].startswith("["):
        end += 1
    current = dict(l.split("=", 1) for l in lines[start + 1:end] if "=" in l)
    if all(current.get(k) == v for k, v in values.items()):
        return
    body = [l for l in lines[start + 1:end] if l.split("=", 1)[0] not in values]
    while body and body[-1] == "":
        body.pop()
    body += [f"{k}={v}" for k, v in values.items()] + [""]
    lines[start + 1:end] = body
    path.write_text("\n".join(lines).rstrip("\n") + "\n")


def session_config(cfg):
    applets = cfg / "plasma-org.kde.plasma.desktop-appletsrc"
    if not applets.exists():
        return
    # The desktop's right-click menu shows only the desktop's own (XP) items: no
    # Enter Edit Mode, Desktop and Wallpaper or Display Configuration.
    off = {k: "false" for k in ["desktop edit mode", "edit mode", "configure", "_display_settings",
                                 "_wallpaper", "manage activities", "remove", "add widgets",
                                 "_add panel", "_run_command", "_lock_screen", "_logout",
                                 "_open_terminal", "configure shortcuts",
                                 "_sep1", "_sep2", "_sep3", "_sep4"]}
    off["_context"] = "true"
    ini_set(applets, ["ActionPlugins", "0", "RightButton;NoModifier"], off)
    # Quick Launch as XP set it up: Show Desktop and the browser (plus Explorer).
    text = applets.read_text()
    m = re.search(r"^\[Containments\]\[(\d+)\]\[Applets\]\[(\d+)\]\n(?:[^\[\n].*\n)*?plugin=org\.kde\.plasma\.quicklaunch",
                  text, re.M)
    if m:
        launchers = [f"file://{APPS / 'xp-show-desktop.desktop'}"]
        ie6 = APPS / "firefox-esr-ie6.desktop"
        if ie6.exists():
            launchers.append(f"file://{ie6}")
        else:
            for app in ["firefox-esr.desktop", "firefox.desktop"]:
                if (Path("/usr/share/applications") / app).exists():
                    launchers.append(f"file:///usr/share/applications/{app}")
                    break
        launchers.append("file:///usr/share/applications/org.kde.dolphin.desktop")
        ini_set(applets, ["Containments", m.group(1), "Applets", m.group(2), "Configuration", "General"],
                {"launcherUrls": ",".join(launchers)})
    log("session settings written")


def show_desktop_launcher():
    APPS.mkdir(parents=True, exist_ok=True)
    q = shutil.which("qdbus6") or shutil.which("qdbus") or "qdbus6"
    (APPS / "xp-show-desktop.desktop").write_text(f"""[Desktop Entry]
Type=Application
Name=Show Desktop
Comment=Minimizes all windows (XP Quick Launch)
Icon=user-desktop
Exec={q} org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "Show Desktop"
NoDisplay=true
X-KaliLooks=winxp
""")


# ---- live: pinned programs as XP had them ------------------------------------------

def pinned_programs():
    stamp = DATA / "winxp-pins.done"
    if stamp.exists():
        return
    agent, activity = "org.kde.plasma.favorites.applications", ":global"
    db = HOME / ".local/share/kactivitymanagerd/resources/database"
    try:
        import sqlite3
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        have = [r[0] for r in con.execute(
            "select targettedResource from ResourceLink where initiatingAgent=?", (agent,))]
        con.close()
    except Exception as e:
        log(f"couldn't read favourites ({e}); left as they are")
        return
    want = ["preferred://browser"]
    for app in ["thunderbird.desktop", "org.kde.kmail2.desktop", "org.gnome.Evolution.desktop"]:
        if (Path("/usr/share/applications") / app).exists():
            want.append("applications:" + app)
            break

    def call(method, res):
        return subprocess.run(
            ["gdbus", "call", "--session", "-d", "org.kde.ActivityManager", "-o",
             "/ActivityManager/Resources/Linking", "-m",
             f"org.kde.ActivityManager.ResourcesLinking.{method}", agent, res, activity],
            capture_output=True, text=True)

    (DATA / "winxp-pins-before.json").write_text(json.dumps(have, indent=1))
    for res in have:
        if res not in want:
            call("UnlinkResourceFromActivity", res)
    for res in want:
        if res not in have:
            call("LinkResourceToActivity", res)
    stamp.write_text("pinned: " + ", ".join(want) + "\n")
    log("Start menu pins set to " + ", ".join(want) + " (old list in winxp-pins-before.json)")


def most_used_programs():
    """XP's Start menu lists the programs you use most. KDE only counts programs
    started from its menus, so on a new look the list is empty: start it with
    programs that are installed here (once; real use takes over from there)."""
    stamp = DATA / "winxp-mfu.done"
    if stamp.exists():
        return
    apps = Path("/usr/share/applications")
    picks = [a for a in ["com.anthropic.Claude.desktop", "org.kde.konsole.desktop",
                         "org.kde.dolphin.desktop", "org.kde.kate.desktop", "discord.desktop",
                         "org.kde.plasma-systemmonitor.desktop"] if (apps / a).exists()]
    for app in reversed(picks):  # the last one counted comes first
        subprocess.run(["gdbus", "call", "--session", "-d", "org.kde.ActivityManager", "-o",
                        "/ActivityManager/Resources", "-m",
                        "org.kde.ActivityManager.Resources.RegisterResourceEvent",
                        "org.kde.plasma.kicker", "0", "applications:" + app, "0"],
                       capture_output=True, text=True)
    stamp.write_text("\n".join(picks) + "\n")
    log("most-used list started with " + ", ".join(picks))


IE6 = HOME / ".local/share/firefox-esr-ie6"
IE6_ADDONS = {
    # CustomTube (lightbeam, MIT): YouTube's layouts back to 2008
    "{7917c4c9-c062-427a-9d29-15db676687eb}": "customtube",
    # Violentmonkey (MIT): runs the old-Google userscript
    "{aecec67f-0d10-4fa7-b7c7-609a2db280cf}": "violentmonkey",
}
# Tried and taken out: PlayerTube's 2006/2010 players come out scrambled on
# YouTube's 2025 ("delhi") player; ie6-youtube-2008.css restyles the player instead.
IE6_BLOCKED = ["{925b0516-774d-469d-bb0e-2b94f199b29a}"]


def ie6_browser(cfg):
    """XP's browser was Internet Explorer: in this look, links open in XPlasma's IE6
    replica (its own Firefox ESR and profile; your usual Firefox is untouched)."""
    if not (IE6 / "launch").exists():
        return
    entry = "firefox-esr-ie6.desktop"
    mime = cfg / "mimeapps.list"
    ini_set(mime, ["Default Applications"],
            {t: entry + ";" for t in ["text/html", "application/xhtml+xml",
                                       "x-scheme-handler/http", "x-scheme-handler/https"]})
    ini_set(cfg / "kdeglobals", ["General"], {"BrowserApplication": entry})
    # Its add-ons for old YouTube and Google, fetched by Firefox from
    # addons.mozilla.org; and no self-updates that could break the IE6 look.
    dist = IE6 / "firefox/distribution"
    dist.mkdir(parents=True, exist_ok=True)
    policies = {"policies": {"DisableAppUpdate": True, "ExtensionSettings": {
        guid: {"installation_mode": "normal_installed",
               "install_url": f"https://addons.mozilla.org/firefox/downloads/latest/{slug}/latest.xpi"}
        for guid, slug in IE6_ADDONS.items()}}}
    for guid in IE6_BLOCKED:
        policies["policies"]["ExtensionSettings"][guid] = {"installation_mode": "blocked"}
    # Websites in light mode, as every site was in XP's day.
    user_js = IE6 / "profile/user.js"
    if user_js.exists():
        js = user_js.read_text()
        pref = 'user_pref("layout.css.prefers-color-scheme.content-override", 1);  // kali-looks\n'
        if pref not in js:
            user_js.write_text(js.rstrip("\n") + "\n" + pref)
    # Our fixes for old YouTube, kept between markers in the profile's userContent.css
    content = IE6 / "profile/chrome/userContent.css"
    ours = (HERE / "ie6-youtube-2008.css").read_text()
    begin, end = "/* >>> kali-looks >>> */\n", "/* <<< kali-looks <<< */\n"
    if content.parent.is_dir():
        old = content.read_text() if content.exists() else ""
        new = re.sub(r"/\* >>> kali-looks >>> \*/\n.*?/\* <<< kali-looks <<< \*/\n", "", old, flags=re.S)
        new = new.rstrip("\n") + "\n\n" + begin + ours + end
        if new != old:
            content.write_text(new)
            log("IE6 browser: old-YouTube fixes updated")
    text = json.dumps(policies, indent=2) + "\n"
    f = dist / "policies.json"
    if not f.exists() or f.read_text() != text:
        f.write_text(text)
        log("IE6 browser: add-ons and no self-updates set")


def ie6_title():
    """The IE6 browser's window title as IE6 wrote it: "Google - Microsoft Internet
    Explorer" instead of "Google — Mozilla Firefox". Two strings in its own copy of
    Firefox (browser/omni.ja), patched once; the original is kept beside it."""
    omni = IE6 / "firefox/browser/omni.ja"
    if not omni.exists() or not shutil.which("zip") or not shutil.which("unzip"):
        return
    ftl, js = "localization/en-US/browser/browser.ftl", "chrome/browser/content/browser/tabbrowser/tabbrowser.js"
    read = lambda name: subprocess.run(["unzip", "-p", str(omni), name], capture_output=True).stdout.decode()
    title_line = "browser-main-window-default-title = Microsoft Internet Explorer"
    if title_line in read(ftl):
        return
    import tempfile
    with tempfile.TemporaryDirectory(prefix="ie6-omni-") as tmp:
        subprocess.run(["unzip", "-q", "-o", str(omni), ftl, js, "-d", tmp], capture_output=True)
        f, j = Path(tmp) / ftl, Path(tmp) / js
        if not f.exists() or not j.exists():
            log("IE6 title: strings not found, left as it is")
            return
        ftext, jtext = f.read_text(), j.read_text()
        old_title = "browser-main-window-default-title = { -brand-full-name }"
        old_join = 'return parts.filter(p => !!p).join(" \u2014 ");'
        if old_title not in ftext or old_join not in jtext:
            log("IE6 title: this Firefox writes its title differently, left as it is")
            return
        f.write_text(ftext.replace(old_title, title_line))
        j.write_text(jtext.replace(old_join, 'return parts.filter(p => !!p).join(" - ");  // kali-looks: IE6'))
        backup = omni.with_name("omni.ja.kali-looks-orig")
        if not backup.exists():
            shutil.copy2(omni, backup)
        # zip -f/-u can't rewrite Mozilla's optimized jar in place: update a plain copy
        work = Path(tmp) / "omni.ja"
        subprocess.run(["unzip", "-q", str(omni), "-d", str(Path(tmp) / "x")], capture_output=True)
        for rel in (ftl, js):
            dst = Path(tmp) / "x" / rel
            dst.write_bytes((Path(tmp) / rel).read_bytes())
        r = subprocess.run(["zip", "-q", "-r", "-9", "-X", "-D", str(work), "."], cwd=Path(tmp) / "x")
        if r.returncode != 0 or not work.exists():
            log("IE6 title: couldn't repack, left as it is")
            return
        staged = omni.with_name("omni.ja.kali-looks-new")
        shutil.copy2(work, staged)
        os.replace(staged, omni)  # a running browser keeps the old file open
    shutil.rmtree(IE6 / "profile/startupCache", ignore_errors=True)
    log("IE6 browser: window title now reads \"… - Microsoft Internet Explorer\"")


def main():
    args = sys.argv[1:]
    if args and args[0] == "--live":
        pinned_programs()
        most_used_programs()
        return
    if not args:
        sys.exit(__doc__)
    cfg = Path(args[0])
    src = args[1] if len(args) > 1 else ""
    user_pictures(src)
    show_desktop_launcher()
    desktop_menu()
    start_menu()
    start_menu_width()
    programs_menus()
    session_config(cfg)
    ie6_browser(cfg)
    ie6_title()


if __name__ == "__main__":
    main()
