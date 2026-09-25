import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import ".."
import "../../config"

// ─────────────────────────────────────────────
// KAIROS COMMAND CENTER — APP LAUNCHER (v0.5)
//
// The launcher is rendered as the COMMAND NEXUS:
// a compact, centered instrument — NOT a menu and
// NOT a search box. The command prompt is the
// NUCLEUS at the bottom of the composition; search
// results ascend from it as NODES on a shared
// vertical SPINE (a 1px command bus), and the
// selected result ENERGIZES the spine segment
// between nucleus and that node.
//
//            COMMAND 03
//              > fire▮
//            ──────────
//    ●                       Firefox        WEB
//    ●  Files
//    ●  Kitty                 TERMINAL
//        │
//        │      (1px spine; the segment down to the
//        │       selected node draws in accent)
//   ↑↓ SELECT · ↵ RUN · ESC CLOSE
//
// SURFACE / GEOMETRY
//   Ephemeral, never part of the permanent shell
//   (exactly two permanent surfaces: TopHud +
//   BottomRail). The window is sized to the nexus
//   column and centered on the output, slightly
//   ELEVATED (Settings.launcherCenterShiftY), so it
//   floats over the desktop's negative space — clear
//   of the HUD above and the rail below, and it only
//   covers input inside its own bounds. exclusiveZone:
//   0 on an overlay surface, so no application window
//   geometry ever changes when it appears/hides.
//
// LAYOUT
//   ≤4 results: wide "breathing" node gap. 5+:
//   compact stack (still on the spine). 1 result:
//   a single node on a short energized stem. 0: a
//   NO MATCH line; the spine is absent (no path).
//
// UNCHANGED (backend contract)
//   State machine, guards, timers, selection, the
//   four IPC entry points and every signal flow are
//   identical to the previous layout. Discovery/
//   search/launch live in AppLauncherService.
// ─────────────────────────────────────────────

PanelWindow {
    id: launcher

    property var fb: null
    property var service: null
    property var commands: null

    screen: launcher.fb !== null && launcher.fb.targetScreen !== null
        ? launcher.fb.targetScreen : null

    // Sized window, centered horizontally by the compositor
    // (bottom-anchor only → niri centers the unanchored axis),
    // with a slight upward elevation; margins are logical px.
    anchors {
        bottom: true
    }

    margins {
        bottom: Math.max(0, (launcher._screenH - launcher.height) / 2
            + Settings.launcherCenterShiftY)
    }

    readonly property real _dpr: launcher.screen !== null
        && launcher.screen.devicePixelRatio > 0 ? launcher.screen.devicePixelRatio : 1
    readonly property real _screenW: launcher.screen !== null
        ? launcher.screen.width : 0
    readonly property real _screenH: launcher.screen !== null
        ? launcher.screen.height : 0

    // The window itself is invisible; the nexus paints.
    color: "transparent"
    implicitHeight: launcher.open ? nexus.height : 1

    // Window is a real sized surface, so the interactive
    // area stays confined to the instrument itself.
    width: Settings.launcherMaxWidth

    exclusiveZone: 0
    aboveWindows: true
    focusable: true

    // ─────────────────────────────────────────
    // VISIBILITY STATE MACHINE (unchanged)
    // ─────────────────────────────────────────

    property string _state: "CLOSED"
    readonly property bool open: launcher._state !== "CLOSED"

    visible: launcher.open

    readonly property real fade: (launcher._state === "OPEN" || launcher._state === "OPENING")
        ? 1 : 0

    property Timer _openTimer: Timer {
        interval: 90
        onTriggered: {
            if (launcher._state === "OPENING") {
                launcher._state = "OPEN"
                launcher._setQueryText("")
                launcher._focusSearch()
                launcher._beginEntrance()
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
        launcher._entranceNodes = 0
        launcher._keyboardMode = false
        launcher._state = "OPENING"
        launcher._openTimer.start()
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
    // NEXUS ENTRANCE (spine, then nodes, ~40ms steps).
    // Restarts only on OPEN — query edits never replay it.
    // ─────────────────────────────────────────

    property int _entranceNodes: 0

    property Timer _stagger: Timer {
        interval: 40
        repeat: true
        onTriggered: {
            const n = launcher.service !== null ? launcher.service.results.length : 0
            const max = Math.min(n, Settings.launcherMaxResults)
            if (launcher._entranceNodes >= max) {
                launcher._stagger.stop()
            } else {
                launcher._entranceNodes++
            }
        }
    }

    function _beginEntrance() {
        const n = launcher.service !== null ? launcher.service.results.length : 0
        if (n > 0) {
            launcher._entranceNodes = 1
            launcher._stagger.start()
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
    // itself (the MouseArea fires entered/position at creation,
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
    // NEXUS GEOMETRY
    // ─────────────────────────────────────────

    readonly property int _resultCount: launcher.service !== null
        ? launcher.service.results.length : 0
    readonly property int _rows: Math.min(launcher._resultCount, Settings.launcherMaxResults)

    // Breathing room when few results, compact stack when many.
    readonly property int _gap: launcher._resultCount > 4
        ? Settings.launcherNodeGapCompact : Settings.launcherNodeGapLoose

    readonly property real _spineX: Math.round(nexus.width / 2) - 0.5

    // Pixel width of the typed command (drives the baseline).
    readonly property real _promptWidth: {
        const f = launcher.searchField
        return f !== null && f !== undefined ? f.promptPixelWidth() : 0
    }

    // Vertical center of the i-th result row, in nexus coords.
    function _rowCenterY(i) {
        return i * (Settings.launcherResultHeight + launcher._gap)
            + Settings.launcherResultHeight / 2
    }

    // ─────────────────────────────────────────
    // SURFACE — THE NEXUS
    // ─────────────────────────────────────────

    Item {
        id: nexus
        width: Settings.launcherMaxWidth
        height: cx.implicitHeight
        opacity: launcher.fade

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animationFast
                easing.type: Theme.easing
            }
        }

        Column {
            id: cx
            width: nexus.width

            // ── RESULT COLUMN ──
            Column {
                id: resultsColumn
                width: nexus.width
                spacing: launcher._gap
                height: launcher._rows * Settings.launcherResultHeight
                    + Math.max(0, launcher._rows - 1) * launcher._gap

                Repeater {
                    model: launcher.service !== null ? launcher.service.results : []

                    LauncherResult {
                        width: resultsColumn.width
                        result: modelData
                        selected: index === launcher._selectedIndex
                        rowHeight: Settings.launcherResultHeight
                        spineX: nexus.width / 2
                        rowIndex: index
                        enterStage: launcher._entranceNodes
                        onRequestSelect: launcher.applyHoverSelect(index)
                        onActivate: launcher.activateSelection()
                    }
                }
            }

            // ── EMPTY STATE (no path on the spine) ──
            HudText {
                visible: launcher._resultCount === 0
                width: nexus.width
                text: "NO MATCH  '" + (launcher.service !== null
                    ? launcher.service.query.trim() : "") + "'"
                color: Theme.subtle
                font.pixelSize: Theme.sizeMicro
                font.letterSpacing: Theme.trackMicro
                horizontalAlignment: Text.AlignHCenter
            }

            // ── GATE ──
            Item {
                width: 1
                height: Settings.launcherGateGap
            }

            // ── COMMAND NUCLEUS ──
            Item {
                id: nucleusRow
                width: nexus.width
                height: nucleusStack.height

                Column {
                    id: nucleusStack
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Settings.launcherPromptWidth
                    spacing: 4

                    // Instrumentation: COMMAND caption + live count.
                    RowLayout {
                        width: parent.width
                        spacing: 8

                        HudLabel {
                            caption: "COMMAND"
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

                    // The prompt itself — the nucleus.
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

                    // Command baseline — hugs the typed text.
                    Rectangle {
                        id: underline
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.max(40, launcher._promptWidth + 24)
                        height: Theme.borderWidth
                        color: Theme.accentDim
                    }
                }
            }

            // ── HINT ──
            HudText {
                width: nexus.width
                text: "↑↓ SELECT    ·    ↵ RUN    ·    ESC CLOSE"
                color: Theme.subtle
                font.pixelSize: Theme.sizeMicro
                font.letterSpacing: 0
                horizontalAlignment: Text.AlignHCenter
            }
        }

        // ── THE SPINE (command bus) ──
        Rectangle {
            id: spine
            x: launcher._spineX
            y: 0
            width: 1
            height: Math.max(0, nucleusRow.y)
            color: Theme.faint
            visible: launcher._resultCount > 0
            opacity: launcher.open && launcher._entranceNodes > 0 ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.animationFast
                    easing.type: Theme.easing
                }
            }
        }

        // Energized path: nucleus → selected node.
        Rectangle {
            id: pathSegment
            x: launcher._spineX
            width: 1
            color: Theme.accent
            visible: launcher._resultCount > 0
            opacity: launcher.open && launcher._entranceNodes > 0 ? 1 : 0
            y: launcher._rowCenterY(
                Math.min(launcher._selectedIndex, Math.max(0, launcher._resultCount - 1)))
            height: Math.max(0, nucleusRow.y - y)

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.animationFast
                    easing.type: Theme.easing
                }
            }
        }
    }
}