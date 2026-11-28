// SPDX-License-Identifier: GPL-3.0-or-later
// kali-looks: the Spotlight magnifying glass of the macOS Tahoe menu bar. Opens KRunner,
// KDE's Spotlight. Drawn with the menu bar button of "macOS Tahoe Shell for KDE"
// (Lester Cordero Murillo and contributors, GPL-3.0), so it matches the other icons.
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import "../../../org.kde.mac-tahoe-liquid-kde.controlcenter/contents/ui" as Controls

PlasmoidItem {
    id: root
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation
    compactRepresentation: null
    toolTipMainText: i18n("Spotlight")

    fullRepresentation: Controls.PanelButton {
        wallpaperTint: Plasmoid.location === PlasmaCore.Types.TopEdge
        symbol: Qt.resolvedUrl("spotlight.svg")
        label: i18n("Spotlight")
        onClicked: root.toggle()
    }
    Connections {
        target: Plasmoid
        function onActivated() { root.toggle(); }
    }
    P5Support.DataSource {
        id: run
        engine: "executable"
        onNewData: source => disconnectSource(source)
    }
    function toggle() {
        run.connectSource("qdbus6 org.kde.krunner /App org.kde.krunner.App.toggleDisplay || krunner");
    }
}
