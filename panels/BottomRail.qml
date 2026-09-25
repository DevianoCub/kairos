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
// visible shell — never middle-of-desktop. It is an
// OVERLAY: `exclusiveZone: 0`, so application window
// geometry never changes when it appears or hides.
// The HUD (top) owns the desktop work-area; the rail
// reserves nothing.
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
// WORKSPACE variant. Visibility is a single
// state machine (HIDDEN / FORCED_REVEAL /
// HOVER_REVEAL / HIDE_PENDING) with exactly one
// auto-hide decision — see below. Disconnect
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
        left: true
        right: true
    }

    // left+right anchored (below) span the full width; only the height is
    // implicit so it can grow/shrink between strip and rail.
    implicitHeight: rail.heightNow
    // The rail is an OVERLAY contextual surface — never a panel:
    //
    //   exclusiveZone: 0  (quickshell's setter forces exclusion-mode Normal)
    //
    // so it reserves ZERO desktop work-area. When it appears, application
    // window geometry MUST NOT change; the rail simply floats over the
    // bottom edge of whatever is beneath it (the HUD owns the top edge).
    exclusiveZone: 0
    aboveWindows: true
    // The window color defaults to white (quickshell docs); the dark slab is
    // painted by the body Rectangle below, so the hidden strip must stay
    // transparent instead of showing an opaque white bar.
    color: "transparent"



    // ─────────────────────────────────────────
    // VISIBILITY STATE MACHINE
    // ─────────────────────────────────────────
    //
    // Exactly ONE decision, ONE rule:
    //
    //     revealed = fForced || fPointer || fGrace
    //
    // Three flags are the only inputs to visibility. Only ONE function
    // (reevaluate) turns them into a state, so no pair of timers ever
    // fights over the visible flag.
    //
    //   HIDDEN          nothing active
    //   FORCED_REVEAL   logical focus/workspace change (fForced)
    //   HOVER_REVEAL    pointer inside the strip (fPointer)
    //   HIDE_PENDING    pointer left, grace still counting (fGrace)
    //
    // fForced is set ONLY by FocusPulse.pulse — which increments only on a
    // logical target change (window or workspace). Title-only edits,
    // telemetry ticks, window metadata and reconnect-to-same-target never
    // pulse, so they never reveal and never restart the timer.
    //
    // The reveal timer is the ONLY auto-hide for forced reveals; the grace
    // timer is the ONLY one for pointer exit. Each clears exactly one flag.

    readonly property bool linked: rail.fb !== null && rail.fb.compositor !== null
        && rail.fb.compositor.connected

    // Flags — the raw inputs to the visibility decision.
    property bool fForced: false      // forced reveal in effect
    property bool fPointer: false     // pointer inside the strip
    property bool fGrace: false       // hover-exit grace still counting

    // The single rule. Nothing else decides visibility.
    readonly property bool revealed: rail.fForced || rail.fPointer || rail.fGrace
    readonly property bool visibleNow: rail.revealed && rail.linked
    readonly property int heightNow: rail.revealed ? Settings.railHeight : Settings.railStripHeight

    // Named visibility state (for deterministic logging).
    property string _state: "HIDDEN"

    function _stateName() {
        if (rail.fForced) return "FORCED_REVEAL"
        if (rail.fPointer) return "HOVER_REVEAL"
        if (rail.fGrace) return "HIDE_PENDING"
        return "HIDDEN"
    }

    // The single state-transition function.
    function reevaluate(reason) {
        const ns = rail._stateName()
        if (ns !== rail._state) {
            console.info(`[Rail] ${rail._state} -> ${ns} reason=${reason}`)
            rail._state = ns
        }
    }

    // True while the child timers exist (a pulse may arrive mid-construction).
    function _timersReady() {
        return rail.revealTimer !== null && rail.revealTimer !== undefined
            && rail.graceTimer !== null && rail.graceTimer !== undefined
    }

    // Logical target change (FocusPulse.pulse): reveal + (re)start the ONE
    // reveal timer. None of these flags is hidden by a non-logical update.
    function forceReveal(reason) {
        if (!rail.linked) return
        if (!rail._timersReady()) {
            // Startup pulse before construction finished: defer one tick.
            Qt.callLater(() => { rail.forceReveal(reason) })
            return
        }
        if (rail._stop(rail.graceTimer)) {
            console.info("[Rail] grace timer stop")
        }
        rail.fGrace = false
        rail.fForced = true
        rail.reevaluate(reason)
        if (!rail._running(rail.revealTimer)) {
            console.info(`[Rail] reveal timer start ${Settings.railRevealMs}ms`)
        } else {
            console.info(`[Rail] reveal timer restart ${Settings.railRevealMs}ms`)
        }
        rail.revealTimer.restart()
    }

    // Hard reset on link loss: nothing may keep the rail visible.
    function resetHidden(reason) {
        if (rail._stop(rail.revealTimer)) {
            console.info("[Rail] reveal timer stop")
        }
        if (rail._stop(rail.graceTimer)) {
            console.info("[Rail] grace timer stop")
        }
        rail.fForced = false
        rail.fPointer = false
        rail.fGrace = false
        rail.reevaluate(reason)
    }

    // True while a timer child exists and is running (children may not yet
    // exist if a signal arrives during early construction).
    function _running(t) {
        return t !== null && t !== undefined && t.running
    }

    function _stop(t) {
        if (rail._running(t)) {
            t.stop()
            return true
        }
        return false
    }

    // ONLY auto-hide for forced reveals. Fires once; afterwards visibility
    // belongs entirely to the pointer/grace flags. Typed properties (not
    // bare child ids) so every consumer can reach them reliably.
    property Timer revealTimer: Timer {
        interval: Settings.railRevealMs
        onTriggered: {
            console.info("[Rail] reveal timer stop")
            rail.fForced = false
            rail.reevaluate("timer")
        }
    }

    // ONLY hover-exit grace.
    property Timer graceTimer: Timer {
        interval: Settings.railHoverGraceMs
        onTriggered: {
            console.info("[Rail] grace timer stop")
            rail.fGrace = false
            rail.reevaluate("grace-expired")
        }
    }

    Connections {
        target: rail.fb
        function onPulseChanged() {
            if (rail.linked) {
                rail.forceReveal(rail.fb !== null && rail.fb.hasWindow
                    ? "focus-change" : "workspace-change")
            }
        }
    }

    onLinkedChanged: {
        if (!rail.linked) {
            rail.resetHidden("disconnect")
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
            if (rail._stop(rail.graceTimer)) {
                console.info("[Rail] grace timer stop")
            }
            rail.fGrace = false
            rail.fPointer = true
            rail.reevaluate("pointer-enter")
        }

        onExited: {
            rail.fPointer = false
            rail.fGrace = true
            rail.graceTimer.restart()
            console.info(`[Rail] grace timer start ${Settings.railHoverGraceMs}ms`)
            rail.reevaluate("pointer-leave")
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