import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import ".."
import "../../config"

// ─────────────────────────────────────────────
// KAIROS COMMAND CENTER — APP LAUNCHER (v0.5)
//
// EPHEMERAL surface, never part of the permanent
// shell. CLOSED is fully unmapped, so at rest the
// desktop keeps EXACTLY two permanent surfaces
// (TopHud + BottomRail); this window exists only
// while OPEN / OPENING / CLOSING.
//
// LAYER SAFETY
//   exclusiveZone: 0 on an overlay surface (same as
//   the rail): ZERO work-area reservation, so no
//   application window ever moves when the launcher
//   appears or disappears. `aboveWindows` floats it
//   over everything; `focusable` lets it take the
//   keyboard for typeahead. Closing releases the
//   keyboard and the compositor re-focuses the
//   previous window — no compositor calls from here.
//
// SURFACE
//   Full-width, bottom-anchored window; the visible
//   palette is a CENTERED column so the command
//   center reads as an instrument, not a dock.
//   Everything outside the column is transparent.
//
// STATE
//   CLOSED -> OPENING -> OPEN -> CLOSING -> CLOSED.
//   Query + selection are the only moving parts and
//   both reset deterministically on open. Text,
//   results and launch execution live in
//   AppLauncherService — this file is view +
//   navigation only. No compositor knowledge.
// ─────────────────────────────────────────────

PanelWindow {
    id: launcher

    property var fb: null
    property var service: null
    property var commands: null

    screen: launcher.fb !== null && launcher.fb.targetScreen !== null
        ? launcher.fb.targetScreen : null

    anchors {
        left: true
        right: true
        bottom: true
    }

    // The window itself is invisible; only the palette
    // sheet paints. (Mirrors the rail's transparent
    // window + painted body approach.)
    color: "transparent"
    // Full-width span forces width = screen width; the
    // palette column centers itself inside.
    implicitHeight: palette.height

    exclusiveZone: 0
    aboveWindows: true
    focusable: true

    // ─────────────────────────────────────────
    // VISIBILITY STATE MACHINE
    // ─────────────────────────────────────────

    property string _state: "CLOSED"
    readonly property bool open: launcher._state !== "CLOSED"

    visible: launcher.open

    readonly property real fade: (launcher._state === "OPEN" || launcher._state === "OPENING")
        ? 1 : 0

    // Fade-in plus late focus hand-off (surface map
    // latency + deferred child instantiation) → turning
    // the keystrokes over to the search field.
    property Timer _openTimer: Timer {
        interval: 90
        onTriggered: {
            if (launcher._state === "OPENING") {
                launcher._state = "OPEN"
                launcher._setQueryText("")
                launcher._focusSearch()
            }
        }
    }

    // The PanelWindow instantiates its content on first
    // show, so child ids are undefined until mapped;
    // every child touch is guarded + deferred above.
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

    // Fade-out completes → fully unmapped.
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
        launcher._state = "OPENING"
        launcher._openTimer.start()
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
    // SELECTION
    // ─────────────────────────────────────────

    property int _selectedIndex: 0

    function moveSelection(delta) {
        const n = launcher.service !== null ? launcher.service.results.length : 0
        if (n <= 0) return
        launcher._selectedIndex = (launcher._selectedIndex + delta + n) % n
    }

    function activateSelection() {
        const r = launcher.service.results[launcher._selectedIndex]
        if (r === undefined || r === null) return
        if (launcher.service.launch(r)) {
            launcher.commands.publishContextual("LAUNCHED " + r.name)
            launcher.close("launch")
        }
    }

    // Scriptable (IPC) entry points mirroring the keyboard
    // handlers exactly: same query set, same selection move,
    // same activation. Used by `qs ipc call` for scripted
    // control and the verification harness.
    function setQueryFromIPC(text) {
        launcher.service.query = text
        launcher._setQueryText(text)
    }

    // Query edits reset the selection; result/model
    // changes keep it in range; both are deterministic.
    Connections {
        target: launcher.service !== null ? launcher.service : launcher
        function onQueryChanged() {
            launcher._selectedIndex = 0
        }
        function onResultsChanged() {
            const n = launcher.service !== null ? launcher.service.results.length : 0
            if (launcher._selectedIndex > n - 1) {
                launcher._selectedIndex = Math.max(0, n - 1)
            }
        }
    }

    // ─────────────────────────────────────────
    // SURFACE
    // ─────────────────────────────────────────

    // The visible palette: a centered, translucent
    // KAIROS sheet with a 1px hairline border.
    Rectangle {
        id: palette
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: Settings.launcherMarginBottom
        }
        width: Settings.launcherWidth
        height: content.height + 20

        color: Theme.surface
        opacity: launcher.fade * 0.96
        border.width: Theme.borderWidth
        border.color: Theme.line

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animationFast
                easing.type: Theme.easing
            }
        }

        // Top hairline — the instrument's single accent.
        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            height: Theme.borderWidth
            color: Theme.accentDim
        }

        Column {
            id: content
            x: 14
            y: 10
            width: parent.width - 28
            spacing: 8

            // ── INSTRUMENTATION ──
            RowLayout {
                width: parent.width
                spacing: 8

                HudLabel {
                    caption: "COMMAND"
                    labelColor: Theme.muted
                    Layout.alignment: Qt.AlignVCenter
                }

                HudText {
                    text: launcher.service !== null
                        ? String(launcher.service.results.length).padStart(2, "0") : "--"
                    color: Theme.accent
                    font.pixelSize: Theme.sizeLabel
                    font.bold: true
                    font.letterSpacing: Theme.trackMicro
                    Layout.alignment: Qt.AlignVCenter
                }

                Item {
                    Layout.fillWidth: true
                }

                HudText {
                    text: "↑↓ SELECT    ENTER RUN    ESC CLOSE"
                    color: Theme.subtle
                    font.pixelSize: Theme.sizeMicro
                    font.letterSpacing: 0
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            // ── SHADE ──
            Rectangle {
                width: parent.width
                height: Theme.borderWidth
                color: Theme.lineSoft
            }

            // ── SEARCH ──
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

            // ── RESULTS ──
            ListView {
                id: list
                width: parent.width
                height: Math.min(
                    launcher.service !== null ? launcher.service.results.length : 0,
                    Settings.launcherMaxResults) * Settings.launcherResultHeight
                model: launcher.service !== null ? launcher.service.results : []
                interactive: false
                clip: true

                delegate: LauncherResult {
                    width: list.width
                    result: modelData
                    selected: index === launcher._selectedIndex
                    rowHeight: Settings.launcherResultHeight
                    onRequestSelect: launcher._selectedIndex = index
                    onActivate: launcher.activateSelection()
                }
            }

            // ── EMPTY STATE ──
            HudText {
                visible: launcher.service !== null
                    && launcher.service.query.trim() !== ""
                    && launcher.service.results.length === 0
                text: "NO MATCH  '" + launcher.service.query.trim() + "'"
                color: Theme.subtle
                font.pixelSize: Theme.sizeMicro
                font.letterSpacing: Theme.trackMicro
            }
        }
    }
}