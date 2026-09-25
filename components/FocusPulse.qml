import Quickshell
import QtQuick

// ─────────────────────────────────────────────
// KAIROS FOCUS PULSE (v0.4)
//
// SINGLE, GLOBAL contextual controller. One
// instance peers from shell.qml into the whole
// desktop and drives the single contextual
// instrument (the bottom rail). There is exactly
// one rail, no matter how many outputs exist.
//
// Consumes ONLY the common CompositorService
// contract. No compositor-specific types, no IPC.
//
// Fingerprint = focused window id | focused
// workspace id. The `pulse` counter increments
// only when the logical target actually changes
// (new window, or workspace switch). Title-only
// edits update `window` in place and never pulse
// — no replay of entrance animations.
//
// `targetScreen` is the Quickshell screen that
// owns the focused workspace (falling back to the
// focused window's output, then the primary
// screen), so the single contextual rail follows
// the user instead of duplicating per output.
//
// On disconnect, state is zeroed and the
// fingerprint reset; a reconnect produces a single
// fresh pulse once state repopulates.
// ─────────────────────────────────────────────

// Non-visual host: Item (zero-size) so it can own
// child QObjects (Connections). Never rendered.
Item {
    id: fb
    width: 0
    height: 0
    visible: false

    property var compositor: null

    // Display state for the UI layer.
    property variant window: null
    property string workspaceId: "--"
    property bool hasWindow: false
    property bool stale: false
    property bool titleOnly: false

    // Attention signal: increments on logical change.
    property int pulse: 0

    // Screen to render the contextual UI on.
    property var targetScreen: fb.primaryScreen

    // Internal fingerprint; "" when there is no live
    // model, so a reconnect always re-pulses once.
    property string _key: ""

    readonly property var primaryScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

    function screenForName(name) {
        if (!name) return null
        const screens = Quickshell.screens
        for (let i = 0; i < screens.length; i++) {
            if (screens[i].name === name) return screens[i]
        }
        return null
    }

    function resolveTargetScreen() {
        const c = fb.compositor
        const out = (c !== null && c !== undefined && c.focusedWorkspace !== null
            && c.focusedWorkspace.output) ? c.focusedWorkspace.output
            : (fb.window !== null && fb.window.output) ? fb.window.output
            : ""
        fb.targetScreen = fb.screenForName(out) || fb.primaryScreen
    }

    function recompute() {
        const c = fb.compositor

        if (c === null || c === undefined || !c.connected) {
            fb.stale = true
            fb.window = null
            fb.hasWindow = false
            fb.workspaceId = "--"
            fb._key = ""
            fb.targetScreen = fb.primaryScreen
            return
        }

        fb.stale = false

        const ws = c.focusedWorkspace
        const idx = ws !== null && ws !== undefined ? ws.index : -1
        fb.workspaceId = idx >= 0 ? String(idx).padStart(2, "0") : "--"

        const w = c.focusedWindow
        fb.window = w
        fb.hasWindow = w !== null && w !== undefined

        // Pre-state (nothing known yet: no window and no
        // workspace mapping) stays silent — no fake pulse.
        if (!fb.hasWindow && idx < 0) {
            fb._key = ""
            fb.titleOnly = true
            fb.targetScreen = fb.primaryScreen
            return
        }

        fb.resolveTargetScreen()

        const id = fb.hasWindow ? String(w.id) : "none"
        const key = id + "|" + (ws !== null && ws !== undefined ? String(ws.id) : "?")

        if (key !== fb._key) {
            fb._key = key
            fb.titleOnly = false
            fb.pulse++
        } else {
            // Same window + same workspace: only details
            // (title, occupancy, ...) may have moved.
            fb.titleOnly = true
        }
    }

    Connections {
        target: fb.compositor
        function onFocusedWindowChanged() { fb.recompute() }
        function onFocusedWorkspaceChanged() { fb.recompute() }
        function onActiveWorkspaceChanged() { fb.recompute() }
        function onWorkspacesChanged() { fb.recompute() }
        function onWindowsChanged() { fb.recompute() }
        function onConnectedChanged() { fb.recompute() }
        function onConnectionStateChanged() { fb.recompute() }
    }

    // Output topology may change at runtime (hotplug):
    // re-resolve the target without pulsing.
    Connections {
        target: Quickshell
        function onScreensChanged() {
            if (fb.compositor !== null && fb.compositor.connected) {
                fb.resolveTargetScreen()
            } else {
                fb.targetScreen = fb.primaryScreen
            }
        }
    }

    onCompositorChanged: fb.recompute()
}