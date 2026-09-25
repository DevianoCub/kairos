import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../components"
import "../config"

// ─────────────────────────────────────────────
// KAIROS FOCUS CAPSULE (v0.4)
//
// THE single focus capsule. Exactly one instance
// exists for the whole shell; it follows the
// screen that owns the focused workspace
// (FocusPulse.targetScreen). Never duplicated per
// output, never stacked.
//
// A small temporary floating instrument shown for
// ~2.5s after a focused-window or workspace
// change:
//
//   ┌──────────────────────────┐
//   │ [K] kitty          WS 02 │
//   │    ~/projects/kairos     │
//   └──────────────────────────┘
//
// Empty-workspace switch renders a workspace-only
// variant:
//
//   ┌─────────────────┐
//   │ WORKSPACE   04  │
//   └─────────────────┘
//
// A new pulse retargets content and restarts the
// timer — a focus change from kitty to firefox
// updates this one sheet; it never accumulates a
// history. Title-only edits update in place
// without replaying the entrance (FocusPulse
// deduplicates by fingerprint).
//
// Non-focusable and tiny (quickshell 0.3.1 has no
// pass-through layer surfaces), with a brief
// lifetime, so its input footprint is negligible.
// Consumes the common CompositorService contract
// via the shared FocusPulse only.
// ─────────────────────────────────────────────

PanelWindow {
    id: cap

    property var fb: null

    // Follow the focused-output screen (single surface).
    screen: cap.fb !== null ? cap.fb.targetScreen : null

    // A single bottom anchor centers the sheet
    // horizontally on that screen.
    anchors {
        bottom: true
    }

    // Offset above the rail strip.
    margins {
        bottom: Settings.focusCapsuleOffset
    }

    // Explicitly non-exclusive so the capsule floats
    // in the free area above the rail's reservation
    // instead of auto-reserving the edge itself.
    exclusiveZone: 0

    implicitWidth: cap.bodyW
    implicitHeight: cap.bodyH
    aboveWindows: true
    focusable: false

    Behavior on implicitWidth {
        NumberAnimation {
            duration: Theme.reducedMotion ? Theme.animationFast : Theme.animationNormal
            easing.type: Theme.easing
        }
    }

    Behavior on implicitHeight {
        NumberAnimation {
            duration: Theme.reducedMotion ? Theme.animationFast : Theme.animationNormal
            easing.type: Theme.easing
        }
    }

    // ─────────────────────────────────────────
    // PULSE / LIFETIME
    // ─────────────────────────────────────────

    readonly property bool linked: cap.fb !== null && cap.fb.compositor !== null
        && cap.fb.compositor.connected

    property bool shown: false
    property int pulseSeen: 0

    readonly property bool wsOnly: cap.shown && (cap.fb === null || !cap.fb.hasWindow)
    readonly property int bodyW: cap.shown ? (cap.wsOnly ? 190 : 260) : 1
    readonly property int bodyH: cap.shown ? (cap.wsOnly ? 30 : 48) : 1

    Connections {
        target: cap.fb
        function onPulseChanged() {
            if (cap.linked && cap.fb.pulse > cap.pulseSeen) {
                cap.pulseSeen = cap.fb.pulse
                cap.shown = true
                life.restart()
            }
        }
    }

    onLinkedChanged: {
        if (!cap.linked) {
            cap.pulseSeen = cap.fb !== null ? cap.fb.pulse : 0
            cap.shown = false
        }
    }

    Timer {
        id: life
        interval: Settings.focusCapsuleMs
        onTriggered: {
            cap.shown = false
        }
    }

    // ─────────────────────────────────────────
    // SURFACE — translucent KAIROS sheet,
    // restrained, NOT a notification toast.
    // ─────────────────────────────────────────

    Rectangle {
        id: bubble
        anchors.fill: parent
        color: Theme.surface
        border.width: Theme.borderWidth
        border.color: Theme.line
        opacity: cap.shown ? 0.92 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.reducedMotion ? Theme.animationFast : Theme.animationNormal
                easing.type: Theme.easing
            }
        }
    }

    HudBracket {
        anchors {
            left: parent.left
            top: parent.top
            leftMargin: 3
            topMargin: 2
        }
        corner: "topLeft"
        markColor: Theme.lineStrong
        opacity: cap.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animationFast
                easing.type: Theme.easing
            }
        }
    }

    HudBracket {
        anchors {
            right: parent.right
            bottom: parent.bottom
            rightMargin: 3
            bottomMargin: 2
        }
        corner: "bottomRight"
        markColor: Theme.accent
        opacity: cap.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animationFast
                easing.type: Theme.easing
            }
        }
    }

    // ─────────────────────────────────────────
    // CONTENT
    // ─────────────────────────────────────────

    ColumnLayout {
        anchors {
            fill: parent
            leftMargin: 12
            rightMargin: 14
            topMargin: 8
            bottomMargin: 8
        }

        spacing: 3

        opacity: cap.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.reducedMotion ? Theme.animationFast : Theme.animationNormal
                easing.type: Theme.easing
            }
        }

        // ── WINDOW VARIANT ──
        RowLayout {
            visible: !cap.wsOnly
            spacing: 10

            // Monogram tile (first letter of app id).
            Rectangle {
                Layout.preferredWidth: 17
                Layout.preferredHeight: 17
                Layout.alignment: Qt.AlignVCenter

                color: Theme.surfaceAlt
                border.width: Theme.borderWidth
                border.color: Theme.line

                HudText {
                    anchors.centerIn: parent
                    text: cap.app.length > 0 ? cap.app.charAt(0).toUpperCase() : "?"
                    color: Theme.accent
                    font.pixelSize: Theme.sizeLabel
                    font.bold: true
                }
            }

            HudText {
                text: cap.app
                color: Theme.textBright
                font.pixelSize: Theme.sizeValue
                font.bold: true
                Layout.alignment: Qt.AlignVCenter
            }

            Item {
                Layout.fillWidth: true
            }

            HudText {
                text: cap.fb !== null ? cap.fb.workspaceId : "--"
                color: Theme.accent
                font.pixelSize: Theme.sizeValue
                font.bold: true
                font.letterSpacing: 2
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // Second identity line, indented under the
        // app id (opaque when there is a title to show).
        HudText {
            visible: !cap.wsOnly && cap.title !== ""
            text: cap.title
            color: Theme.muted
            font.pixelSize: Theme.sizeMicro
            Layout.leftMargin: 27
            Layout.fillWidth: true
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignLeft
        }

        // ── WORKSPACE-ONLY VARIANT ──
        RowLayout {
            visible: cap.wsOnly
            spacing: 10

            HudLabel {
                caption: "WORKSPACE"
                labelColor: Theme.muted
                Layout.alignment: Qt.AlignVCenter
            }

            Item {
                Layout.fillWidth: true
            }

            HudText {
                text: cap.fb !== null ? cap.fb.workspaceId : "--"
                color: Theme.accent
                font.pixelSize: Theme.sizeValue
                font.bold: true
                font.letterSpacing: 2
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    // ─────────────────────────────────────────
    // IDENTITY HELPERS (common descriptor only)
    // ─────────────────────────────────────────

    readonly property string app: {
        const w = cap.fb !== null ? cap.fb.window : null
        if (w === null || w === undefined) return ""
        if (w.appId && w.appId.trim() !== "") return w.appId
        if (w.title && w.title.trim() !== "") return w.title
        return "win"
    }

    readonly property string title: {
        const w = cap.fb !== null ? cap.fb.window : null
        if (w === null || w === undefined) return ""
        return w.title ? w.title.trim() : ""
    }
}