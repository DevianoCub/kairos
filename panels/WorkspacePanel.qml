import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../components"
import "../config"

// ─────────────────────────────────────────────
// KAIROS WORKSPACE MATRIX (v0.3)
//
// Per-screen read-only view of the Niri workspace
// strip. Consumes NiriService only — never touches
// Niri IPC itself.
//
//   WORKSPACES  eDP-1
//     01   02   03   04   05
//     ▲     ▬   ...
//
// Connected : matrix cells, ▲ caret + accent rail on
//             the focused workspace, dots for occupied.
// Disconnected: restrained "NIRI ○ OFFLINE" — no faked data.
//
// The window hangs under the TopHUD without reserving
// screen space (layer-shell anchors have no margins, so
// the offset is a transparent head region = HUD height).
// ─────────────────────────────────────────────

PanelWindow {
    id: wksp

    property var modelData
    property var niriService: null

    screen: modelData

    anchors {
        top: true
        left: true
    }

    implicitWidth: wksp.bodyWidth
    implicitHeight: Settings.hudHeight + Settings.wkspPanelOffset + wksp.innerHeight
    exclusiveZone: Settings.exclusiveZone
    aboveWindows: true
    visible: Settings.showWorkspacePanel

    // ─────────────────────────────────────────────
    // DATA
    // ─────────────────────────────────────────────

    readonly property string output: modelData !== undefined && modelData !== null ? modelData.name : ""

    readonly property bool offline: wksp.niriService === null || !wksp.niriService.connected

    readonly property variant mine: wksp.offline
        ? []
        : wksp.niriService.workspacesFor(wksp.output).slice(0, Settings.workspacesMaxCells)

    readonly property int mineCount: wksp.mine.length
    readonly property int cellsWidth: Math.max(1, wksp.mineCount) * Settings.wkspCellWidth

    // Index of the display workspace (focused, else active) within this strip.
    readonly property int focusedCol: {
        if (wksp.offline) {
            return -1
        }

        for (let i = 0; i < wksp.mine.length; i++) {
            if (wksp.mine[i].isFocused) {
                return i
            }
        }

        for (let i = 0; i < wksp.mine.length; i++) {
            if (wksp.mine[i].isActive) {
                return i
            }
        }

        return -1
    }

    readonly property int padX: 12
    readonly property int headerWidth: 96 + 8 + 46 + 10

    readonly property int innerHeight: 18 + 6 + 40 + 5
    readonly property int bodyWidth: wksp.padX * 2 + Math.max(wksp.headerWidth, wksp.cellsWidth)

    // ─────────────────────────────────────────────
    // SURFACE
    // ─────────────────────────────────────────────

    Rectangle {
        anchors.fill: parent
        color: Theme.surface
        opacity: 0.98
    }

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
            leftMargin: 3
            bottomMargin: Theme.borderWidth - 1
        }
        corner: "bottomLeft"
        markColor: Theme.lineStrong
    }

    // ─────────────────────────────────────────────
    // CONTENT
    // ─────────────────────────────────────────────

    Column {
        id: content
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: wksp.padX
            rightMargin: wksp.padX
            bottomMargin: 5
        }

        spacing: 6

        // ── HEADER ──
        Row {
            spacing: 10

            HudLabel {
                caption: "workspaces"
                anchors.verticalCenter: parent.verticalCenter
            }

            HudText {
                text: wksp.output
                color: Theme.subtle
                font.pixelSize: Theme.sizeMicro
                font.letterSpacing: Theme.trackMicro
                anchors.verticalCenter: parent.verticalCenter
            }

            HudText {
                text: "× " + wksp.mineCount
                color: Theme.muted
                font.pixelSize: Theme.sizeMicro
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // ── MATRIX / OFFLINE ──
        Item {
            width: wksp.cellsWidth
            height: 40

            // Offline: nothing fabricated.
            Row {
                visible: wksp.offline
                anchors.centerIn: parent
                spacing: 8

                HudLabel {
                    caption: "niri"
                    anchors.verticalCenter: parent.verticalCenter
                }

                HudText {
                    text: "○ offline"
                    color: Theme.muted
                    font.pixelSize: Theme.sizeLabel
                    font.letterSpacing: Theme.trackLabel
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Connected but empty mapping for this output.
            HudText {
                visible: !wksp.offline && wksp.mineCount === 0
                anchors.centerIn: parent
                text: "◦ no mapping"
                color: Theme.subtle
                font.pixelSize: Theme.sizeMicro
                font.letterSpacing: Theme.trackMicro
            }

            // ── CARET (▲ over the focused column) ──
            HudText {
                visible: wksp.focusedCol >= 0
                text: "▲"
                color: Theme.accent
                font.pixelSize: Theme.sizeMicro
                x: wksp.focusedCol * Settings.wkspCellWidth + Settings.wkspCellWidth / 2 - 3
                y: 0

                Behavior on x {
                    NumberAnimation {
                        duration: Theme.animationFast
                        easing.type: Theme.easing
                    }
                }
            }

            HudText {
                visible: wksp.focusedCol >= 0
                text: "ACTIVE"
                color: Theme.accent
                font.pixelSize: Theme.sizeMicro
                font.letterSpacing: Theme.trackMicro
                x: wksp.focusedCol * Settings.wkspCellWidth + Settings.wkspCellWidth + 3
                y: 2

                Behavior on x {
                    NumberAnimation {
                        duration: Theme.animationFast
                        easing.type: Theme.easing
                    }
                }
            }

            // ── CELLS ──
            Repeater {
                model: wksp.mine

                delegate: Item {
                    readonly property int col: index
                    readonly property var ws: modelData

                    width: Settings.wkspCellWidth
                    height: 40
                    x: index * Settings.wkspCellWidth

                    HudText {
                        text: String(ws.idx + 1).padStart(2, "0")
                        color: {
                            if (ws.isFocused) return Theme.textBright
                            if (ws.isActive) return Theme.accentDim
                            return Theme.muted
                        }
                        font.pixelSize: Theme.sizeValue
                        font.bold: ws.isFocused
                        font.letterSpacing: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 11
                    }

                    // Occupied / urgent marker.
                    Rectangle {
                        width: 3
                        height: 3
                        y: 28
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: ws.urgent ? Theme.warning : (ws.windowCount > 0 ? Theme.lineStrong : "transparent")
                        visible: ws.urgent || ws.windowCount > 0
                    }
                }
            }

            // ── BASELINE + FOCUS RAIL ──
            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                }

                y: 36
                height: 1
                color: Theme.lineSoft
            }

            Rectangle {
                visible: wksp.focusedCol >= 0
                x: wksp.focusedCol * Settings.wkspCellWidth + 4
                y: 32
                width: Settings.wkspCellWidth - 8
                height: 2
                color: Theme.accent

                Behavior on x {
                    NumberAnimation {
                        duration: Theme.animationFast
                        easing.type: Theme.easing
                    }
                }
            }
        }
    }
}