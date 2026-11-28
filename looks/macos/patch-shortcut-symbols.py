#!/usr/bin/env python3
"""kali-looks: keyboard shortcuts in menus written the Mac way.

Menus show "Ctrl+Shift+N"; a Mac writes the same thing as "⌃⇧N": modifier symbols in
Apple's order (⌃ Control, ⌥ Option/Alt, ⇧ Shift, ⌘ Command, which is the Super key
here) and then the key, with ↩ ⌫ ⌦ ⎋ ⇥ and arrows for the special ones. The symbols
name the keys you actually press: Ctrl stays ⌃, it doesn't turn into ⌘.

Patches the Tahoe Shell's menu style (desktop and app menus) and the menu bar's own
menus (Apple and Finder menus) before they're built; safe to run again.

  patch-shortcut-symbols.py <macos-tahoe source tree>
"""
import sys
from pathlib import Path

MARK = "kali-looks: Mac shortcut symbols"

CONVERTER = r'''
// ''' + MARK + '''
static QString kaliLooksMacShortcut(const QString &text)
{
    const QKeySequence sequence = QKeySequence::fromString(text, QKeySequence::NativeText);
    if (sequence.count() != 1 || sequence[0].key() == Qt::Key_unknown) return text;
    const QKeyCombination chord = sequence[0];
    const Qt::KeyboardModifiers mods = chord.keyboardModifiers();
    QString out;
    if (mods & Qt::ControlModifier) out += QChar(0x2303);
    if (mods & Qt::AltModifier) out += QChar(0x2325);
    if (mods & Qt::ShiftModifier) out += QChar(0x21E7);
    if (mods & Qt::MetaModifier) out += QChar(0x2318);
    switch (chord.key()) {
    case Qt::Key_Return: case Qt::Key_Enter: out += QChar(0x21A9); break;
    case Qt::Key_Backspace: out += QChar(0x232B); break;
    case Qt::Key_Delete: out += QChar(0x2326); break;
    case Qt::Key_Escape: out += QChar(0x238B); break;
    case Qt::Key_Tab: case Qt::Key_Backtab: out += QChar(0x21E5); break;
    case Qt::Key_Left: out += QChar(0x2190); break;
    case Qt::Key_Right: out += QChar(0x2192); break;
    case Qt::Key_Up: out += QChar(0x2191); break;
    case Qt::Key_Down: out += QChar(0x2193); break;
    case Qt::Key_Home: out += QChar(0x2196); break;
    case Qt::Key_End: out += QChar(0x2198); break;
    case Qt::Key_PageUp: out += QChar(0x21DE); break;
    case Qt::Key_PageDown: out += QChar(0x21DF); break;
    case Qt::Key_Space: out += QStringLiteral("Space"); break;
    default: out += QKeySequence(chord.key()).toString(QKeySequence::NativeText);
    }
    return out;
}
'''

# 1) the Qt menu style: every menu row's shortcut, before it's drawn
STYLE = "src/offline/menu-style/menu_style.cpp"
STYLE_ANCHOR_INC = "#include <QWindow>\n"
STYLE_ANCHOR_NS = "namespace {\n"
STYLE_OLD = '''        const auto *row = qstyleoption_cast<const QStyleOptionMenuItem *>(option);
        if (element != CE_MenuItem'''
STYLE_NEW = '''        const auto *row = qstyleoption_cast<const QStyleOptionMenuItem *>(option);
        QStyleOptionMenuItem macRow;
        if (element == CE_MenuItem && row && row->text.contains(QLatin1Char('\\t')) && themed(widget)) {
            macRow = *row;
            macRow.text = row->text.section(QLatin1Char('\\t'), 0, 0) + QLatin1Char('\\t')
                + kaliLooksMacShortcut(row->text.section(QLatin1Char('\\t'), 1));
            row = &macRow;
            option = &macRow;
        }
        if (element != CE_MenuItem'''

# 2) the menu bar's own menus (Apple, Finder and apps' menus in the bar)
MENU = "src/offline/plasmoids/org.kde.mac.tahoe.liquid.globalmenu/systemmenustyle.h"
MENU_OLD = '''        const auto sequence = QKeySequence::fromString(shortcut, QKeySequence::NativeText);
        if (sequence == QKeySequence(Qt::CTRL | Qt::META | Qt::Key_Q)) return QStringLiteral("⌃⌘Q");
        if (sequence == QKeySequence(Qt::SHIFT | Qt::META | Qt::Key_Q)) return QStringLiteral("⇧⌘Q");
        return shortcut;'''
MENU_NEW = '''        return kaliLooksMacShortcut(shortcut); // ''' + MARK


def patch(path, edits):
    s = path.read_text()
    if MARK in s:
        return "already"
    for old, new in edits:
        if old not in s:
            return None
        s = s.replace(old, new, 1)
    path.write_text(s)
    return "patched"


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    src = Path(sys.argv[1])
    style = patch(src / STYLE, [
        (STYLE_ANCHOR_INC, STYLE_ANCHOR_INC + "#include <QKeySequence>\n"),
        (STYLE_ANCHOR_NS, STYLE_ANCHOR_NS + CONVERTER),
        (STYLE_OLD, STYLE_NEW),
    ])
    menu_file = src / MENU
    m = menu_file.read_text()
    first_include = m.find("#include")
    menu = patch(menu_file, [
        (m[first_include:m.find("\n", first_include) + 1],
         m[first_include:m.find("\n", first_include) + 1] + "#include <QKeySequence>\n#include <QString>\n" + CONVERTER),
        (MENU_OLD, MENU_NEW),
    ]) if first_include >= 0 else None
    if style is None or menu is None:
        sys.exit(f"shortcut symbols: source changed upstream (style: {style}, menu bar: {menu})")
    print(f"shortcut symbols: menu style {style}, menu bar {menu}")


if __name__ == "__main__":
    main()
