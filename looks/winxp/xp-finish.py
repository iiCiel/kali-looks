#!/usr/bin/env python3
"""kali-looks: finishing touches that make XPlasma Plus match Windows XP.

Usage: xp-finish.py CONFIG_DIR [XPLASMA_SRC]  (files only; run while Plasma isn't running)
       xp-finish.py --live                    (things that need the running session)

Every change is idempotent (marked "kali-looks") and only touches the XP look:
XPlasma's own widgets in ~/.local/share/plasma and the XP look's config folder.
"""
import json
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


def main():
    args = sys.argv[1:]
    if args and args[0] == "--live":
        pinned_programs()
        return
    if not args:
        sys.exit(__doc__)
    cfg = Path(args[0])
    src = args[1] if len(args) > 1 else ""
    user_pictures(src)
    show_desktop_launcher()
    desktop_menu()
    start_menu()
    session_config(cfg)


if __name__ == "__main__":
    main()
