import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../components"
import "../config"

// ─────────────────────────────────────────────
// KAIROS BOTTOM CONTEXTUAL RAIL (v0.4)
//
// THE single contextual surface. Exactly one
// instance exists for the whole shell; it follows
// the screen that owns the focused workspace
// (FocusPulse.targetScreen). It is never
// duplicated per output.
//
// Hidden = a 12px transparent hover strip only;
// revealed = a 36px rail that grows upward
// (bottom-anchored, so content slides up into view).
// The strip hugs the actual bottom edge of the
// visible shell — never middle-of-desktop.
//
//   hidden:  ···· (transparent hover strip)
//   shown:   ───────────────────────────────
//            [K] kitty   ~/projects/kairos  WS 03
//            ───────────────────────────────
//   empty:   ───────────────────────────────
//            WORKSPACE   03
//            ───────────────────────────────
//
// Its primary purpose is active-window context:
// a focused-window change reveals the identity
// row; a workspace-only change reveals a
// WORKSPACE variant. Both auto-dismiss after
// railRevealMs. A pointer over the strip reveals
// the rail too (with an exit grace). Disconnect
// reverts to the bare strip. Nothing is ever
// fabricated — a quiet idle stays fully
// invisible.
//
// No clock: time already lives in the TopHUD.
// Nothing here duplicates the HUD.
//
// Consumes the common CompositorService contract
// via the shared FocusPulse only.
// ─────────────────────────────────────────────

PanelWindow {
    id: rail

    property var fb: null

    screen: rail.fb !== null ? rail.fb.targetScreen : null

    anchors {
        bottom: true
    }

    implicitWidth: rail.fb !== null && rail.fb.targetScreen !== null ? rail.fb.targetScreen.width : 1536
    implicitHeight: rail.heightNow
    // The rail is the only bottom-edge surface: it reserves its own
    // strip/rail height so it stays pinned to the true bottom edge for
    // every hide/reveal cycle.
    exclusiveZone: rail.heightNow
    aboveWindows: true
    // The window color defaults to white (quickshell docs); the dark slab is
    // painted by the body Rectangle below, so the hidden strip must stay
    // transparent instead of showing an opaque white bar.
    color: "transparent"



    // ─────────────────────────────────────────
    // REVEAL STATE
    // ─────────────────────────────────────────

    readonly property bool linked: rail.fb !== null && rail.fb.compositor !== null
        && rail.fb.compositor.connected

    property bool hovered: false
    property bool forced: false
    property bool revealed: rail.hovered || rail.forced

    readonly property bool visibleNow: rail.revealed && rail.linked
    readonly property int heightNow: rail.revealed ? Settings.railHeight : Settings.railStripHeight

    Connections {
        target: rail.fb
        function onPulseChanged() {
            if (rail.linked) {
                rail.forceShow()
            }
        }
    }

    onLinkedChanged: {
        if (!rail.linked) {
            rail.dismiss()
        }
    }

    function forceShow() {
        rail.forced = true
        forcedHide.restart()
    }

    function dismiss() {
        rail.forced = false
        rail.hovered = false
    }

    Timer {
        id: hoverGrace
        interval: Settings.railHoverGraceMs
        onTriggered: {
            rail.hovered = false
        }
    }

    Timer {
        id: forcedHide
        interval: Settings.railRevealMs
        onTriggered: {
            if (!rail.hovered) {
                rail.forced = false
            }
        }
    }

    // ─────────────────────────────────────────
    // INPUT STRIP (always present for hover)
    // ─────────────────────────────────────────

    MouseArea {
        id: strip
        anchors.fill: parent
        hoverEnabled: true
        enabled: Settings.railHoverReveal

        onEntered: {
            hoverGrace.stop()
            rail.hovered = true
        }

        onExited: {
            if (MouseArea.containsMouse === false) {
                hoverGrace.restart()
            }
        }
    }

    // ─────────────────────────────────────────
    // SURFACE
    // ─────────────────────────────────────────

    // Translucent KAIROS panel surface, matching the
    // top HUD / workspace matrix language — NOT a
    // solid black slab.
    Rectangle {
        id: body
        anchors.fill: parent
        color: Theme.surface
        opacity: rail.visibleNow ? 0.96 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animationFast
                easing.type: Theme.easing
            }
        }
    }

    // Rail hairline sits along the top edge of the
    // surface; growing the surface upward visibly
    // slides it up with the content.
    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: Theme.borderWidth
        color: Theme.line
        opacity: rail.visibleNow ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animationFast
                easing.type: Theme.easing
            }
        }
    }

    HudBracket {
        anchors {
            left: parent.left
            top: parent.top
            leftMargin: 4
            topMargin: Theme.borderWidth - 1
        }
        corner: "topLeft"
        markColor: Theme.lineStrong
        opacity: rail.visibleNow ? 1 : 0

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
            top: parent.top
            rightMargin: 4
            topMargin: Theme.borderWidth - 1
        }
        corner: "topRight"
        markColor: Theme.lineStrong
        opacity: rail.visibleNow ? 1 : 0

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

    // Bottom-anchored at rail height: when the sheet
    // grows from strip to rail the block rises into
    // view like an instrument, never clipped mid-glyph.
    RowLayout {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: 14
            rightMargin: 14
        }

        height: Settings.railHeight

        opacity: rail.visibleNow ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.reducedMotion ? Theme.animationFast : Theme.animationNormal
                easing.type: Theme.easing
            }
        }

        // ── WINDOW CONTEXT (primary purpose) ──
        WindowIdentity {
            id: identity
            visible: rail.fb !== null && rail.fb.hasWindow
            window: rail.fb !== null && rail.fb.hasWindow ? rail.fb.window : null
            titleWidth: 220
            Layout.alignment: Qt.AlignVCenter
        }

        // ── WORKSPACE-CONTEXT VARIANT ──
        // Empty-workspace switch: the rail still answers
        // "where am I", in the same language.
        Row {
            visible: rail.fb === null || !rail.fb.hasWindow
            spacing: 10
            Layout.alignment: Qt.AlignVCenter

            HudLabel {
                caption: "WORKSPACE"
                labelColor: Theme.muted
            }

            HudText {
                text: rail.fb !== null ? rail.fb.workspaceId : "--"
                color: Theme.accent
                font.pixelSize: Theme.sizeValue
                font.bold: true
                font.letterSpacing: 2
            }
        }

        Item {
            Layout.fillWidth: true
        }

        // ── WORKSPACE RELATIONSHIP (window context only) ──
        HudLabel {
            visible: rail.fb !== null && rail.fb.hasWindow && rail.fb.workspaceId !== "--"
            caption: "WS"
            labelColor: Theme.subtle
            Layout.alignment: Qt.AlignVCenter
        }

        HudText {
            visible: rail.fb !== null && rail.fb.hasWindow && rail.fb.workspaceId !== "--"
            text: rail.fb !== null ? rail.fb.workspaceId : "--"
            color: Theme.accent
            font.pixelSize: Theme.sizeValue
            font.bold: true
            font.letterSpacing: 2
            Layout.alignment: Qt.AlignVCenter
            Layout.leftMargin: 8
            Layout.topMargin: 1
        }
    }
}