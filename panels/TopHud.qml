import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../components"
import "../config"

// ─────────────────────────────────────────────
// KAIROS TOP HUD
//
// The overlay bar (v0.2). Runs once per screen as a
// layer-shell panel, reserves no screen space, and
// renders live system state without touching the
// compositor layout.
// ─────────────────────────────────────────────

PanelWindow {
    id: hud

    property var modelData

    screen: modelData

    anchors {
        top: true
        left: true
        right: true
    }

    implicitHeight: Settings.hudHeight
    exclusiveZone: Settings.exclusiveZone

    // Pure overlay: float above application windows.
    aboveWindows: true

    // ─────────────────────────────────────────────
    // SURFACE
    // ─────────────────────────────────────────────

    Rectangle {
        anchors.fill: parent
        color: Theme.background
        opacity: 0.98
    }

    // ─────────────────────────────────────────────
    // BOTTOM FRAME / HAIRLINE
    // ─────────────────────────────────────────────

    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }

        height: Theme.borderWidth
        color: Theme.line
    }

    HudBracket {
        anchors {
            left: parent.left
            bottom: parent.bottom
            leftMargin: 4
            bottomMargin: Theme.borderWidth - 1
        }
        corner: "bottomLeft"
        markColor: Theme.lineStrong
    }

    HudBracket {
        anchors {
            right: parent.right
            bottom: parent.bottom
            rightMargin: 4
            bottomMargin: Theme.borderWidth - 1
        }
        corner: "bottomRight"
        markColor: Theme.lineStrong
    }

    // ─────────────────────────────────────────────
    // MAIN ROW
    // ─────────────────────────────────────────────

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 4
        anchors.bottomMargin: 5

        spacing: 0

        // ── ACCENT TICK ──
        Rectangle {
            width: 2
            height: 18
            color: Theme.accent
            Layout.alignment: Qt.AlignVCenter
        }

        Item {
            Layout.preferredWidth: 16
        }

        // ── IDENT ──
        HudText {
            text: "KAIROS"
            color: Theme.textBright
            font.pixelSize: Theme.sizeTitle
            font.bold: true
            font.letterSpacing: Theme.trackTitle
            Layout.alignment: Qt.AlignVCenter
        }

        HudText {
            text: "//  SYSTEM-07"
            color: Theme.subtle
            font.pixelSize: Theme.sizeMicro
            font.letterSpacing: Theme.trackMicro
            Layout.alignment: Qt.AlignVCenter
            Layout.leftMargin: 10
        }

        Item {
            Layout.preferredWidth: Theme.gutSpacing
        }

        // ── STATUS ──
        StatusLight {
            status: hud.systemService.status
            dotSize: 7
            Layout.alignment: Qt.AlignVCenter
        }

        HudLabel {
            caption: hud.systemService.statusLabel
            labelColor: hud.systemService.status === "ok" ? Theme.ok : Theme.accent
            Layout.alignment: Qt.AlignVCenter
            Layout.leftMargin: 7
        }

        Item {
            Layout.preferredWidth: Theme.gutSpacing
        }

        // ── WORKSPACE INDEX (v0.3, Niri only) ──
        Metric {
            label: "WKSP"
            value: hud.wkspLabel
            visible: hud.niriService !== null && hud.niriService.connected
            Layout.alignment: Qt.AlignVCenter
        }

        Item {
            Layout.preferredWidth: Theme.gutSpacing
        }

        // ── SEPARATOR ──
        HudLine {
            orientation: Qt.Vertical
            color: Theme.line
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignVCenter
            Layout.leftMargin: 2
            Layout.rightMargin: 2
        }

        Item {
            Layout.preferredWidth: Theme.gutSpacing
        }

        // ── CENTER STRETCH ──
        Item {
            Layout.fillWidth: true
        }

        // ── COMPOSITOR LINK ──
        HudLabel {
            caption: "COMPOSITOR"
            Layout.alignment: Qt.AlignVCenter
        }

        HudText {
            text: hud.systemService.compositorName
            color: Theme.accent
            font.pixelSize: Theme.sizeValue
            font.bold: true
            Layout.alignment: Qt.AlignVCenter
            Layout.leftMargin: 12
        }

        Item {
            Layout.fillWidth: true
        }

        // ── SEPARATOR ──
        HudLine {
            orientation: Qt.Vertical
            color: Theme.line
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignVCenter
            Layout.leftMargin: 2
            Layout.rightMargin: 2
        }

        Item {
            Layout.preferredWidth: Theme.gutSpacing
        }

        // ── RIGHT METRIC BANK ──
        Metric {
            label: "MEM"
            value: hud.systemService.memoryPercent
            Layout.alignment: Qt.AlignVCenter
        }

        Item {
            Layout.preferredWidth: Theme.gutSpacing
        }

        Metric {
            label: "LOAD"
            value: hud.systemService.loadAverage
            Layout.alignment: Qt.AlignVCenter

            valueColor: {
                const load = hud.systemService.loadOne
                if (load >= 4.0) return Theme.warning
                if (load >= 2.0) return Theme.accent
                return Theme.textBright
            }
        }

        Item {
            Layout.preferredWidth: Theme.gutSpacing
        }

        Metric {
            label: "UP"
            value: hud.systemService.uptimeText
            Layout.alignment: Qt.AlignVCenter
        }

        Item {
            Layout.preferredWidth: Theme.gutSpacing
        }

        // ── TELEMETRY BANK (v0.2) ──

        // CPU
        Row {
            Layout.alignment: Qt.AlignVCenter
            spacing: Theme.spacing

            HudLabel {
                caption: "CPU"
                anchors.verticalCenter: parent.verticalCenter
            }

            Gauge {
                value: hud.systemService.cpuPercentValue
                width: 52
                height: 10
                anchors.verticalCenter: parent.verticalCenter
            }

            HudText {
                text: hud.systemService.cpuPercent
                color: {
                    const status = hud.systemService.status
                    if (status === "critical") return Theme.critical
                    if (status === "warning") return Theme.warning
                    return Theme.textBright
                }
                font.pixelSize: Theme.sizeValue
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Item {
            Layout.preferredWidth: Theme.gutSpacing
        }

        // NET
        Row {
            Layout.alignment: Qt.AlignVCenter
            spacing: Theme.spacing

            HudLabel {
                caption: "NET"
                anchors.verticalCenter: parent.verticalCenter
            }

            Graph {
                samples: hud.systemService.netRxHistory
                maxValue: 0
                width: 56
                height: 14
                anchors.verticalCenter: parent.verticalCenter
            }

            HudText {
                text: "RX"
                color: Theme.subtle
                font.pixelSize: Theme.sizeMicro
                anchors.verticalCenter: parent.verticalCenter
            }

            HudText {
                text: hud.systemService.netRxText
                color: Theme.accent
                font.pixelSize: Theme.sizeValue
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }

            HudText {
                text: "TX"
                color: Theme.subtle
                font.pixelSize: Theme.sizeMicro
                anchors.verticalCenter: parent.verticalCenter
            }

            HudText {
                text: hud.systemService.netTxText
                color: Theme.textBright
                font.pixelSize: Theme.sizeValue
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Item {
            Layout.preferredWidth: Theme.gutSpacing
        }

        // TEMP
        Metric {
            label: "TMP"
            value: hud.systemService.temperatureText
            visible: hud.systemService.temperatureText !== "N/A"
            Layout.alignment: Qt.AlignVCenter

            valueColor: {
                const value = hud.systemService.temperatureValue
                if (value >= 80) return Theme.critical
                if (value >= 70) return Theme.warning
                return Theme.textBright
            }
        }

        Item {
            Layout.preferredWidth: Theme.gutSpacing
        }

        // ── DATE / CLOCK ──
        HudText {
            visible: Settings.showDate
            text: hud.systemService.currentDate
            color: Theme.muted
            font.pixelSize: Theme.sizeMicro
            font.letterSpacing: Theme.trackMicro
            Layout.alignment: Qt.AlignVCenter
            Layout.rightMargin: 14
        }

        HudText {
            text: hud.systemService.currentTime
            color: Theme.textBright
            font.pixelSize: Theme.sizeTitle + 2
            font.bold: true
            font.letterSpacing: 2
            Layout.alignment: Qt.AlignVCenter
        }
    }

    // Service instance owned by the shell, injected from shell.qml.
    property var systemService: null
    property var niriService: null

    // Compact workspace index chip (Niri only). "--" when the
    // link is down or the screen has no workspace mapping.
    property string wkspLabel: {
        const niri = hud.niriService

        if (niri === null || !niri.connected) {
            return "--"
        }

        const screenName = hud.screen !== undefined && hud.screen !== null ? hud.screen.name : ""
        const idx = niri.displayIndexFor(screenName)

        return idx >= 0 ? String(idx + 1).padStart(2, "0") : "--"
    }
}