#!/usr/bin/env python3
"""kali-looks: macOS Tahoe's lock screen for the Tahoe look.

Tahoe's lock screen: the date over a large translucent ("glass") time near the top,
and a small photo with your name near the bottom; the password field shows when you
move the mouse or type. Plasma 6.7 keeps its lock screen inside its desktop shell
package, so this makes a copy of that package with a changed LockScreenUi.qml. The
copy is rebuilt from the system's own files whenever they change (Plasma updates come
through), and kali-looks links it into place only while the Tahoe look runs (as it does
for XP's). If Plasma's lock screen code changes so the edits no longer fit, the copy is
removed and the stock lock screen is used.

  lockscreen.py <look config tree>
"""
import hashlib
import shutil
import sys
from pathlib import Path

HOME = Path.home()
SYSTEM = Path("/usr/share/plasma/shells/org.kde.plasma.desktop")
REL = ".local/share/plasma/shells/org.kde.plasma.desktop"
VERSION = "4"

CLOCK_OLD = '''        Clock {
            id: clock
            property Item shadow: clockShadow
            visible: y > 0 && config.alwaysShowClock
            anchors.horizontalCenter: parent.horizontalCenter
            y: (mainBlock.userList.y + mainStack.y)/2 - height/2
            Layout.alignment: Qt.AlignBaseline
        }
'''
CLOCK_NEW = '''        // kali-looks: macOS Tahoe's lock screen clock: the date over a large glass time
        Column {
            id: clock
            property Item shadow: clockShadow
            property date now: new Date()
            visible: config.alwaysShowClock
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(lockScreenRoot.height * 0.08)
            spacing: -Math.round(lockScreenRoot.height * 0.012)
            Timer {
                interval: 1000; running: true; repeat: true; triggeredOnStart: true
                onTriggered: clock.now = new Date()
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.locale().toString(clock.now, "ddd MMM d")
                color: Qt.rgba(1, 1, 1, 0.92)
                font.family: "SF Pro Display"
                font.weight: Font.DemiBold
                font.pixelSize: Math.round(lockScreenRoot.height * 0.03)
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                // 12-hour, no AM/PM, as on a Mac
                text: Qt.locale().toString(clock.now, "h:mm AP").replace(/\\s*[AaPp]\\.?[Mm]\\.?$/, "")
                color: Qt.rgba(1, 1, 1, 0.74)
                font.family: "SF Pro Display"
                font.weight: Font.Bold
                font.pixelSize: Math.round(lockScreenRoot.height * 0.15)
            }
        }
'''
SHADOW_OLD = "            color : Qt.rgba(0, 0, 0, 0.7)\n"
SHADOW_NEW = "            color : Qt.rgba(0, 0, 0, 0.3) // kali-looks: Tahoe's faint shadow\n"
STACK_OLD = '''            height: lockScreenRoot.height + Kirigami.Units.gridUnit * 3
            focus: true //StackView is an implicit focus scope'''
STACK_NEW = '''            height: lockScreenRoot.height + Kirigami.Units.gridUnit * 3
            // kali-looks: photo, name and password near the bottom, as on a Mac (a
            // transform: the on-screen keyboard's helper owns y)
            transform: Translate { y: Math.round(lockScreenRoot.height * 0.30) }
            focus: true //StackView is an implicit focus scope'''
BLOCK_OLD = '''                lockScreenUiVisible: lockScreenRoot.uiVisible
'''
BLOCK_NEW = '''                lockScreenUiVisible: lockScreenRoot.uiVisible
                // kali-looks: a small photo and name, and no Sleep/Switch User buttons
                userList.scale: 0.55
                userList.transformOrigin: Item.Bottom
                actionItemsVisible: false
'''
FIELD_OLD = '"@info:placeholder in text field", "Password")'
FIELD_NEW = '"@info:placeholder in text field", "Enter Password")'
# Plasma ships the fingerprint/smartcard PAM services even without a reader, so the
# "(or scan your …)" hints show on every machine; a Mac shows none of that
FINGER_OLD = "        kind: ScreenLocker.Authenticator.Fingerprint\n"
FINGER_NEW = FINGER_OLD + "        visible: false // kali-looks\n"
CARD_OLD = "        kind: ScreenLocker.Authenticator.Smartcard\n"
CARD_NEW = CARD_OLD + "        visible: false // kali-looks\n"
UI = "contents/lockscreen/LockScreenUi.qml"
EDITS = [(UI, CLOCK_OLD, CLOCK_NEW), (UI, SHADOW_OLD, SHADOW_NEW), (UI, STACK_OLD, STACK_NEW),
         (UI, BLOCK_OLD, BLOCK_NEW),
         ("contents/lockscreen/MainBlock.qml", FIELD_OLD, FIELD_NEW),
         ("contents/lockscreen/MainBlock.qml", FINGER_OLD, FINGER_NEW),
         ("contents/lockscreen/MainBlock.qml", CARD_OLD, CARD_NEW)]


def log(msg):
    print(f"lockscreen: {msg}")


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    tree = Path(sys.argv[1])
    store = tree / ".home" / REL
    link = HOME / REL
    ui = SYSTEM / "contents/lockscreen/LockScreenUi.qml"
    if not ui.exists():
        return
    stamp_text = VERSION + hashlib.sha256(
        b"".join(p.read_bytes() for p in sorted(SYSTEM.rglob("*")) if p.is_file())).hexdigest()
    stamp = store / ".kali-looks"
    if not (stamp.exists() and stamp.read_text() == stamp_text):
        patched = {}
        for rel, old, new in EDITS:
            text = patched.get(rel) or (SYSTEM / rel).read_text()
            if old not in text:
                shutil.rmtree(store, ignore_errors=True)
                if link.is_symlink() and not link.exists():
                    link.unlink()
                log("Plasma's lock screen changed; using the stock one")
                return
            patched[rel] = text.replace(old, new, 1)
        shutil.rmtree(store, ignore_errors=True)
        shutil.copytree(SYSTEM, store, symlinks=True)
        for rel, text in patched.items():
            (store / rel).write_text(text)
        stamp.write_text(stamp_text)
        log("Tahoe lock screen built")
    # kali-looks links a look's files in before the session; on the first run there
    # was nothing to link yet
    if not link.exists() and not link.is_symlink():
        link.parent.mkdir(parents=True, exist_ok=True)
        link.symlink_to(store)
        log("Tahoe lock screen linked in")


if __name__ == "__main__":
    main()
