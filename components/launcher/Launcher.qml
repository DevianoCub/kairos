import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "file:/home/jupy/.config/quickshell/kairos/components"
import "file:/home/jupy/.config/quickshell/kairos/config"

// ─────────────────────────────────────────────
// KAIROS COMMAND CENTER — APP LAUNCHER (v0.5)
//
// The launcher is a compact, centered COMMAND PANEL:
// a stable opaque dark surface that reads identically
// over any wallpaper (bright, dark, red, photographic).
// No backdrop transparency, no decorative art.
//
//            KAIROS COMMAND    07
//            ────────────────────
//            > firefox▌
//            ──────────
//            │ Firefox                    WEB
//              Files                      SYSTEM
//              Kitty                      TERMINAL
//            ────────────────────
//            ↑↓ SELECT · ↵ RUN · ESC CLOSE
//
// Layout is strictly KAIROS: monospace, thin lines,
// small tracked captions, primary/secondary text
// hierarchy, restrained accent, generous negative
// space. The prompt is the focus of the panel; the
// caret is always visible while focused.
//
// SURFACE / GEOMETRY
//   Ephemeral, never part of the permanent shell
//   (exactly two permanent surfaces: TopHud +
//   BottomRail). Sized to the panel column, centered
//   on the output, ELEVATED (Settings.launcherCenterShiftY)
//   so it floats over negative space clear of HUD and
//   rail. exclusiveZone: 0 → no application window
//   geometry ever changes when it appears/hides.
//
// UNCHANGED (backend contract)
//   State machine, guards, timers, selection, the four
//   IPC entry points and every signal flow. Discovery,
//   search and launch live in AppLauncherService
//   (real desktop-entry index — nothing hardcoded).
//   Typing, Backspace, ↑↓, ↵, ESC all flow through
//   LauncherSearch → the service, on the exact same
//   code paths the keyboard uses.
// ─────────────────────────────────────────────

PanelWindow {
    id: launcher

    property var fb: null
    property var service: null
    property var commands: null

    screen: launcher.fb !== null && launcher.fb.targetScreen !== null
        ? launcher.fb.targetScreen : null

    // Sized window, centered horizontally by an explicit left margin; a
    // slight upward elevation. Margins are logical px.
    //
    // Runs inside the DEDICATED single-window launcher process
    // (kairos-launcher). A fresh surface mapped with Exclusive keyboard
    // interactivity is the ONLY configuration this compositor forwards
    // real keystrokes to, so this window must stay the sole layer surface
    // of its process.
    anchors {
        bottom: true
        left: true
    }

    margins {
        bottom: Math.max(0, (launcher._screenH - launcher.height) / 2
            + Settings.launcherCenterShiftY)
        left: Math.max(0, (launcher._screenW - Math.max(0, launcher.width)) / 2)
    }

    readonly property real _dpr: launcher.screen !== null
        && launcher.screen.devicePixelRatio > 0 ? launcher.screen.devicePixelRatio : 1
    readonly property real _screenW: launcher.screen !== null
        ? launcher.screen.width : 0
    readonly property real _screenH: launcher.screen !== null
        ? launcher.screen.height : 0

    // The window itself is invisible; the opaque panel paints.
    color: "transparent"
    implicitHeight: launcher.open ? nexus.height : 1

    // Real sized surface, so the interactive area stays
    // confined to the instrument itself.
    width: Settings.launcherMaxWidth

    exclusiveZone: 0
    aboveWindows: true
    // quickshell's WindowInterface must track keyboard for this window
    // (focusable) AND niri must actually grant keyboard without a click
    // (Exclusive interactivity via the attached layer-shell object).
    // The Overlay layer keeps the launcher reachable above fullscreen
    // windows; Top-layer exclusivity is not auto-focused by niri.
    focusable: true
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible
        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // ─────────────────────────────────────────
    // VISIBILITY STATE MACHINE (unchanged)
    // ─────────────────────────────────────────

    property string _state: "CLOSED"
    readonly property bool open: launcher._state !== "CLOSED"

    visible: launcher.open

    readonly property real fade: (launcher._state === "OPEN" || launcher._state === "OPENING")
        ? 1 : 0

    property Timer _openTimer: Timer {
        interval: 60
        onTriggered: {
            if (launcher._state === "OPENING") {
                launcher._state = "OPEN"
                launcher._setQueryText("")
                launcher._focusSearch()
            }
        }
    }

    function _setQueryText(t) {
        const f = launcher.searchField
        if (f !== null && f !== undefined) f.setQuery(t)
    }

    function _focusSearch() {
        const f = launcher.searchField
        if (f !== null && f !== undefined) f.forceFocus()
    }

    function _releaseSearch() {
        const f = launcher.searchField
        if (f !== null && f !== undefined) f.releaseFocus()
    }

    property Timer _closeTimer: Timer {
        interval: Theme.animationFast
        onTriggered: {
            if (launcher._state === "CLOSING") {
                launcher._state = "CLOSED"
            }
        }
    }

    function openLauncher(reason) {
        if (launcher.open) return
        if (launcher.fb === null) return
        launcher.service.query = ""
        launcher._selectedIndex = 0
        launcher._keyboardMode = false
        launcher._state = "OPENING"
        launcher._openTimer.start()
        // The input is focused and the caret shown the instant the
        // launcher opens — typing works immediately.
        launcher._focusSearch()
        launcher._armHoverGuard()
        console.info(`[Launcher] open reason=${reason}`)
    }

    function close(reason) {
        if (!launcher.open) return
        launcher._state = "CLOSING"
        launcher._releaseSearch()
        launcher._closeTimer.start()
        console.info(`[Launcher] close reason=${reason}`)
    }

    function toggle(reason) {
        if (launcher.open) {
            launcher.close(reason !== undefined && reason !== null ? reason : "toggle")
        } else {
            launcher.openLauncher(reason !== undefined && reason !== null ? reason : "toggle")
        }
    }

    // ─────────────────────────────────────────
    // SELECTION (unchanged logic)
    // ─────────────────────────────────────────

    property int _selectedIndex: 0

    function moveSelection(delta) {
        const n = launcher.service !== null ? launcher.service.results.length : 0
        if (n <= 0) return
        launcher._keyboardMode = true
        launcher._selectedIndex = (launcher._selectedIndex + delta + n) % n
    }

    function activateSelection() {
        launcher._keyboardMode = true
        const r = launcher.service.results[launcher._selectedIndex]
        if (r === undefined || r === null) return
        if (launcher.service.launch(r)) {
            launcher.commands.publishContextual("LAUNCHED " + r.name)
            launcher.close("launch")
        }
    }

    function setQueryFromIPC(text) {
        launcher.service.query = text
        launcher._setQueryText(text)
    }

    // Synthetic-hover guard: a freshly-instantiated delegate
    // under a stationary cursor would otherwise re-select
    // itself (the MouseArea fires enter/position at creation,
    // on rebuild and on the config/re-expose cycle). Covers
    // the round-trip window; real movement later selects.
    property real _hoverGuardUntil: 0

    // Once the keyboard drives the selection, hover hands off:
    // repaint-driven hover re-entries must never overwrite it.
    property bool _keyboardMode: false

    function applyHoverSelect(index) {
        if (launcher._keyboardMode) return
        if (Date.now() < launcher._hoverGuardUntil) return
        launcher._selectedIndex = index
    }

    function _armHoverGuard() {
        // Re-arms on every result change so the selection
        // stays deterministic while the query is live.
        launcher._hoverGuardUntil = Date.now() + 800
    }

    Connections {
        target: launcher.service !== null ? launcher.service : launcher
        function onQueryChanged() {
            launcher._selectedIndex = 0
            launcher._keyboardMode = false
        }
        function onResultsChanged() {
            const n = launcher.service !== null ? launcher.service.results.length : 0
            if (launcher._selectedIndex > n - 1) {
                launcher._selectedIndex = Math.max(0, n - 1)
            }
            launcher._armHoverGuard()
        }
    }

    // ─────────────────────────────────────────
    // COMMAND PANEL GEOMETRY
    // ─────────────────────────────────────────

    readonly property int _resultCount: launcher.service !== null
        ? launcher.service.results.length : 0
    readonly property int _rows: Math.min(launcher._resultCount, Settings.launcherMaxResults)

    // Breathing room when few results, compact stack when many.
    readonly property int _gap: launcher._resultCount > 4
        ? Settings.launcherNodeGapCompact : Settings.launcherNodeGapLoose

    // Pixel width of the typed command (drives the prompt baseline).
    readonly property real _promptWidth: {
        const f = launcher.searchField
        return f !== null && f !== undefined ? f.promptPixelWidth() : 0
    }

    // True when the TextInput (or its LauncherSearch wrapper) has
    // active focus — proves "focused at open, type immediately".
    readonly property bool inputFocused: launcher.searchField !== null
        && launcher.searchField !== undefined && launcher.searchField.activeFocus

    // TEMP DIAG (remove after verification)
    readonly property string dbgFocus: {
        const f = launcher.searchField
        if (f === null || f === undefined) return "SEARCH NULL internal"
        let node = f, out = `focus=${f.activeFocus} vis=${f.visible} en=${f.enabled}`
        let p = f.parent
        let d = 0
        while (p !== null && d < 10) {
            out += `|${d}:v${p.visible}e${p.enabled}o${p.opacity}`
            p = p.parent
            d++
        }
        return out
    }

    // ─────────────────────────────────────────
    // SURFACE — THE COMMAND PANEL
    // ─────────────────────────────────────────

    Item {
        id: nexus
        width: Settings.launcherMaxWidth
        height: cx.implicitHeight + Settings.launcherPanelPadding * 2
        opacity: launcher.fade

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animationFast
                easing.type: Theme.easing
            }
        }

        // Stable opaque surface: fully readable over any wallpaper.
        Rectangle {
            anchors.fill: parent
            color: Theme.surface
            border.color: Theme.line
            border.width: Theme.borderWidth
            radius: Theme.radius

            Column {
                id: cx
                anchors.fill: parent
                anchors.margins: Settings.launcherPanelPadding
                spacing: 0

                // ── HEADER ──
                RowLayout {
                    width: parent.width
                    spacing: 8

                    HudLabel {
                        caption: "KAIROS COMMAND"
                        labelColor: Theme.muted
                    }

                    Item { Layout.fillWidth: true }

                    HudText {
                        text: launcher.service !== null
                            ? String(launcher.service.results.length).padStart(2, "0") : "--"
                        color: Theme.accent
                        font.pixelSize: Theme.sizeLabel
                        font.bold: true
                        font.letterSpacing: Theme.trackMicro
                    }
                }

                Item { height: Settings.launcherHeaderGap; width: 1 }

                // ── HEADER RULE ──
                Rectangle {
                    width: parent.width
                    height: Theme.borderWidth
                    color: Theme.lineSoft
                }

                Item { height: Settings.launcherHeaderGap; width: 1 }

                // ── COMMAND INPUT ──
                LauncherSearch {
                    id: searchField
                    width: parent.width

                    onQueryTextChanged: {
                        if (launcher.service !== null) {
                            launcher.service.query = text
                        }
                    }
                    onNavUp: launcher.moveSelection(-1)
                    onNavDown: launcher.moveSelection(1)
                    onSubmit: launcher.activateSelection()
                    onDismiss: launcher.close("escape")
                }

                Item { height: 2; width: 1 }

                // Prompt baseline — hugs the typed command.
                Rectangle {
                    id: underline
                    width: Math.max(40, launcher._promptWidth + 24)
                    height: 2
                    color: Theme.accentDim
                }

                Item { height: Settings.launcherInputGap; width: 1 }

                // ── RESULTS ──
                Column {
                    id: resultsColumn
                    width: parent.width
                    spacing: launcher._gap

                    Repeater {
                        model: launcher.service !== null ? launcher.service.results : []

                        LauncherResult {
                            width: resultsColumn.width
                            result: modelData
                            selected: index === launcher._selectedIndex
                            rowHeight: Settings.launcherResultHeight
                            onRequestSelect: launcher.applyHoverSelect(index)
                            onActivate: launcher.activateSelection()
                        }
                    }

                    // ── EMPTY STATE ──
                    HudText {
                        visible: launcher._resultCount === 0
                        width: parent.width
                        text: "NO MATCH  '" + (launcher.service !== null
                            ? launcher.service.query.trim() : "") + "'"
                        color: Theme.subtle
                        font.pixelSize: Theme.sizeMicro
                        font.letterSpacing: Theme.trackMicro
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                Item { height: Settings.launcherInputGap; width: 1 }

                // ── HINT ──
                HudText {
                    width: parent.width
                    text: "↑↓ SELECT    ·    ↵ RUN    ·    ESC CLOSE"
                    color: Theme.subtle
                    font.pixelSize: Theme.sizeMicro
                    font.letterSpacing: 0
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }
}