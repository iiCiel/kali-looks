#!/usr/bin/env python3
"""Small fixes kali-looks applies to its unpacked copy of the XPlasma Plus installer.

Run with the installer's folder. Each fix is applied once (marked "kali-looks"), and the
installer's own checksum list is updated so its self-check still passes.
"""
import hashlib
import json
import sys
from pathlib import Path

base = Path(sys.argv[1])
FIXES = [
    # ~/.config is a link to this look's own (plain) folder; ~/.local and ~/.icons are
    # links in the hidden setup session. Its backups are fine with that.
    ("backend.py",
     "   if path.is_symlink():links.add(str(path))",
     "   if path.is_symlink() and path not in {home/'.config',home/'.local',home/'.icons'}:links.add(str(path))  # kali-looks"),
    # Its build-dependency step turned every "deb" line into "deb-src" instead of adding
    # one, so with one-line .list sources (Kali) no binary packages were left.
    ("dependencies.py",
     "   else:text=re.sub(r'^(\\s*)deb\\s',r'\\1deb-src ',text,flags=re.M)",
     "   else:text=text+'\\n'+re.sub(r'^(\\s*)deb\\s',r'\\1deb-src ',text,flags=re.M)  # kali-looks"),
    # Loading/unloading effects in the running KWin is only a live preview; the settings
    # are written either way. Don't fail the install when the (hidden) KWin can't.
    ("payload/tools/xp-behavior.py",
     "    for effect in DISABLED:\n        run(DBUS, 'org.kde.KWin', '/Effects',\n            'org.kde.kwin.Effects.unloadEffect', effect)\n    run(DBUS, 'org.kde.KWin', '/Effects',\n        'org.kde.kwin.Effects.loadEffect', 'fadingpopups')",
     "    for effect in DISABLED:  # kali-looks: live preview only\n        subprocess.run([DBUS, 'org.kde.KWin', '/Effects', 'org.kde.kwin.Effects.unloadEffect', effect], check=False)\n    subprocess.run([DBUS, 'org.kde.KWin', '/Effects', 'org.kde.kwin.Effects.loadEffect', 'fadingpopups'], check=False)"),
]

# Fixes inside the XPlasma source archive that the installer compiles from.
TAR_FIXES = [
    # Maximized windows kept their title-bar buttons where the window's right edge had
    # been: KWin 6.7 (X11) can report a maximize before the new width arrives.
    ("source/xplasma-source.tar.gz", "xplasma/src/decoration/decoration.cpp",
     """    connect(w, &KDecoration3::DecoratedWindow::sizeChanged, this, layoutAndPaint);
    connect(w, &KDecoration3::DecoratedWindow::maximizedChanged, this, layoutAndPaint);""",
     """    connect(w, &KDecoration3::DecoratedWindow::sizeChanged, this, layoutAndPaint);
    // kali-looks: KWin 6.7 (X11) can report a maximize before the window has its
    // new width; follow the width itself, and look again once the change settles.
    connect(w, &KDecoration3::DecoratedWindow::widthChanged, this, layoutAndPaint);
    connect(w, &KDecoration3::DecoratedWindow::heightChanged, this, layoutAndPaint);
    connect(w, &KDecoration3::DecoratedWindow::maximizedChanged, this, [this, layoutAndPaint] {
        layoutAndPaint();
        QTimer::singleShot(0, this, layoutAndPaint);
    });"""),
]

# Display Properties' Settings tab (screen resolution and monitor arrangement), as in XP:
# xp-settings-tab.cpp, added to XPlasma Plus Properties ahead of the dialog's own code.
_tab = (Path(__file__).resolve().parent / "xp-settings-tab.cpp").read_text()
TAB_INCLUDES = "".join(l + "\n" for l in _tab.splitlines() if l.startswith("#include"))
TAB_CODE = "".join(l + "\n" for l in _tab.splitlines() if not l.startswith("#include"))
DP = "xplasma/src/app/editor/displayproperties.cpp"
SRC = "source/xplasma-source.tar.gz"
TAR_FIXES += [
    (SRC, DP, "#include <QVBoxLayout>\n", "#include <QVBoxLayout>\n" + TAB_INCLUDES),
    (SRC, DP, "} // namespace\n\nDisplayProperties::DisplayProperties(QWidget *parent)",
     "} // namespace\n\n" + TAB_CODE + "DisplayProperties::DisplayProperties(QWidget *parent)"),
    (SRC, DP, '    m_tabs->addTab(appearanceTab(), QStringLiteral("Appearance"));\n',
     '    m_tabs->addTab(appearanceTab(), QStringLiteral("Appearance"));\n'
     '    m_xpSettings = new XpSettingsTab; // kali-looks: XP\'s Settings tab\n'
     '    m_xpSettings->changed = [this] { updateApply(); };\n'
     '    m_tabs->addTab(m_xpSettings, QStringLiteral("Settings"));\n'
     '    m_tabs->setUsesScrollButtons(false); // every tab in sight, as in XP\n'),
    (SRC, DP, "|| m_hidpiStart->isChecked() != m_appliedHiDpiStart);",
     "|| m_hidpiStart->isChecked() != m_appliedHiDpiStart || (m_xpSettings && m_xpSettings->pending()));"),
    (SRC, DP, "    const Look l = look();\n    const Wallpaper desktop = wallpaper();\n    // Shift: everything",
     "    if (m_xpSettings && !m_xpSettings->apply()) // kali-looks\n        return false;\n"
     "    const Look l = look();\n    const Wallpaper desktop = wallpaper();\n    // Shift: everything"),
    (SRC, "xplasma/src/app/editor/displayproperties.h", "    SoundsTab *m_sounds;\n",
     "    SoundsTab *m_sounds;\n    class XpSettingsTab *m_xpSettings = nullptr; // kali-looks\n"),
    (SRC, "xplasma/src/app/editor/main.cpp",
     "    parser.addOption(soundsOption);\n",
     "    parser.addOption(soundsOption);\n"
     "    const QCommandLineOption settingsOption(QStringLiteral(\"settings\"), QStringLiteral(\"XPlasma Plus Properties, on its Settings tab.\")); // kali-looks\n"
     "    parser.addOption(settingsOption);\n"),
    (SRC, "xplasma/src/app/editor/main.cpp",
     "        dialog.showTab(QStringLiteral(\"Sounds\"));\n",
     "        dialog.showTab(QStringLiteral(\"Sounds\"));\n"
     "    if (parser.isSet(settingsOption)) // kali-looks\n        dialog.showTab(QStringLiteral(\"Settings\"));\n"),
]


def patch_text(text, old, new, where):
    """One fix to a file's text: unchanged if it's already there."""
    if new in text:
        return text
    if text.count(old) != 1:
        sys.exit(f"patch-xplasma: expected code not found in {where}")
    return text.replace(old, new)


def patch_tar(archive, member, old, new):
    import io
    import tarfile
    with tarfile.open(archive) as t:
        members = [(m, t.extractfile(m).read() if m.isfile() else None) for m in t.getmembers()]
    changed = False
    for i, (m, data) in enumerate(members):
        if m.name != member:
            continue
        text = data.decode()
        if new in text:
            return False
        if text.count(old) != 1:
            sys.exit(f"patch-xplasma: expected code not found in {member}")
        data = text.replace(old, new).encode()
        m.size = len(data)
        members[i] = (m, data)
        changed = True
    if not changed:
        sys.exit(f"patch-xplasma: {member} not in {archive.name}")
    tmp = archive.with_suffix(".kali-looks.tmp")
    with tarfile.open(tmp, "w:gz") as t:
        for m, data in members:
            t.addfile(m, io.BytesIO(data) if data is not None else None)
    tmp.replace(archive)
    return True


sums_file = base / "SHA256SUMS.json"
sums = json.loads(sums_file.read_text())
for name, old, new in FIXES:
    f = base / name
    text = f.read_text()
    if new in text:
        continue
    if text.count(old) != 1:
        sys.exit(f"patch-xplasma: expected code not found in {name}")
    f.write_text(text.replace(old, new))
    if name in sums:
        sums[name] = hashlib.sha256(f.read_bytes()).hexdigest()
for name, member, old, new in TAR_FIXES:
    archive = base / name
    if archive.exists() and patch_tar(archive, member, old, new) and name in sums:
        sums[name] = hashlib.sha256(archive.read_bytes()).hexdigest()
sums_file.write_text(json.dumps(sums, indent=2) + "\n")
