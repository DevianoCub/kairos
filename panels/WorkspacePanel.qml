import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../components"
import "../config"

// ─────────────────────────────────────────────
// KAIROS WORKSPACE MATRIX (v0.3.1)
//
// Per-screen read-only view of the desktop
// workspace strip. Consumes the common
// CompositorService contract only — no socket,
// no compositor-specific protocol, no IPC.
//
//   WORKSPACES  eDP-1
//      ▲
//     01   02   03   04   05
//     ▮    ▒          ▒
//
// Connected : matrix cells with a thin status rail
//             under each column (focused = accent,
//             occupied = strong line, urgent =
//             warning, empty = quiet). ▲ caret and
//             ACTIVE tag mark the display workspace.
// Disconnected: restrained offline state — state is
//             never fabricated.
//
// The window hangs under the TopHUD without
// reserving screen space (layer-shell anchors have
// no margins, so the offset is a transparent head
// region = HUD height).
// ─────────────────────────────────────────────

PanelWindow {
    id: wksp

    property var modelData
    property var compositor: null

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
    // DATA (common desktop-state contract only)
    // ─────────────────────────────────────────────

    readonly property string output: modelData !== undefined && modelData !== null ? modelData.name : ""

    readonly property bool offline: wksp.compositor === null || !wksp.compositor.connected

    readonly property variant mine: wksp.offline
        ? []
        : wksp.compositor.workspacesFor(wksp.output).slice(0, Settings.workspacesMaxCells)

    readonly property int mineCount: wksp.mine.length
    readonly property int cellsWidth: Math.max(1, wksp.mineCount) * Settings.wkspCellWidth

    // Column of the display workspace (focused, else
    // active) within this strip, or -1.
    readonly property int focusedCol: {
        if (wksp.offline) {
            return -1
        }

        return wksp.compositor.displayColumnFor(wksp.output)
    }

    // Offline readout — distinguishes "KAIROS has no
    // backend for this compositor" from "backend link
    // is down".
    readonly property string linkCaption: {
        if (wksp.compositor === null || wksp.compositor.name === "") {
            return "desktop"
        }

        return wksp.compositor.name
    }

    readonly property string linkValue: {
        if (wksp.compositor === null || wksp.compositor.connectionState === "unsupported") {
            return "◦ no backend"
        }

        if (wksp.compositor.connectionState === "connecting") {
            return "○ link"
        }

        return "○ offline"
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
                    caption: wksp.linkCaption
                    anchors.verticalCenter: parent.verticalCenter
                }

                HudText {
                    text: wksp.linkValue
                    color: Theme.muted
                    font.pixelSize: Theme.sizeLabel
                    font.letterSpacing: Theme.trackLabel
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Connected but no workspace mapping for this
            // output.
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
                        text: wksp.compositor.workspaceLabel(ws)
                        color: {
                            if (ws.isFocused) return Theme.textBright
                            if (ws.isActive) return Theme.accentDim
                            return Theme.muted
                        }
                        font.pixelSize: Theme.sizeValue
                        font.bold: ws.isFocused
                        font.letterSpacing: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 10
                    }

                    // Status rail: active = accent, occupied =
                    // strong line, urgent = warning, idle = quiet.
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 34
                        width: Settings.wkspCellWidth - 8
                        height: 2
                        color: ws.isUrgent ? Theme.warning : (ws.isFocused ? Theme.accent : (ws.occupied ? Theme.lineStrong : "transparent"))
                    }
                }
            }

            // ── BASELINE ──
            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                }

                y: 36
                height: 1
                color: Theme.lineSoft
            }
        }
    }
}