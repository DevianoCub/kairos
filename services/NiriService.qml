import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// ─────────────────────────────────────────────
// KAIROS NIRI SERVICE (v0.3)
//
// Read-only bridge to the Niri compositor IPC.
// Speaks the raw UNIX-socket protocol directly:
//
//   connect  →  wait for full-state events over the
//               EventStream (single persistent socket,
//               newline-delimited JSON), no subprocess.
//   events   →  WorkspacesChanged / WindowsChanged are
//               authoritative full replacements.
//               WorkspaceActivated ({id, focused} in
//               niri ≥26) drives optimistic focus moves.
//   failure  →  connected=false, exp. backoff retry.
//
// Never issues commands to Niri in this milestone.
// The panel layer binds to state exposed here only.
//
// Exposed state:
//   connected / connectionState / socketPath
//   workspaces / activeWorkspaces / focusedWorkspace
//   windows / focusedWindow / outputs
//   workspacesFor(op), displayIndexFor(op), windowCounts
// ─────────────────────────────────────────────

Item {
    id: niri
    width: 0
    height: 0
    visible: false

    // ─────────────────────────────────────────────
    // CONNECTION STATE
    // ─────────────────────────────────────────────

    property bool connected: false
    property string connectionState: "disconnected" // disconnected | connecting | connected
    readonly property string socketPath: Quickshell.env("NIRI_SOCKET")

    // ─────────────────────────────────────────────
    // STRUCTURED STATE (UI binds here)
    // ─────────────────────────────────────────────

    // Workspace objects: { id, name, idx, output, isFocused,
    //                      isActive, urgent, activeWindowId, windowCount }.
    property variant workspaces: []

    // Light window objects: { id, title, appId, workspaceId, isFocused }.
    property variant windows: []

    property variant focusedWorkspace: null // focused workspace, or null
    property variant activeWorkspace: null    // focused if any, else first active
    property variant activeWorkspaces: []
    property variant focusedWindow: null
    property variant outputs: []

    signal workspaceActivated(real id, bool focused)

    // ─────────────────────────────────────────────
    // SOCKET / PARSER
    // Quickshell.Io.Socket is a QLocalSocket. The SplitParser
    // feeds us one JSON event per newline-delimited line.
    // ─────────────────────────────────────────────

    Socket {
        id: niriSocket
        parser: niriSplitter

        onConnectionStateChanged: {
            if (niriSocket.connected && !niri._wasConnected) {
                niri.onLinkUp()
            } else if (!niriSocket.connected && niri._wasConnected) {
                niri.onLinkLost("socket disconnected")
            }

            niri._wasConnected = niriSocket.connected
        }

        onError: (error) => niri.onLinkLost("socket error " + error)
    }

    SplitParser {
        id: niriSplitter
        splitMarker: "\n"

        onRead: (data) => niri.handleLine(data)
    }

    Timer {
        id: retryTimer
        interval: Settings.niriRetryMinMs

        onTriggered: niri.tryConnect()
    }

    // ─────────────────────────────────────────────
    // LIFECYCLE
    // ─────────────────────────────────────────────

    function tryConnect() {
        if (niri.connected || niriSocket.connected) {
            return
        }

        const path = niri.socketPath

        if (path === "") {
            niri.connectionState = "disconnected"
            niri.scheduleRetry()
            return
        }

        niriSocket.path = path
        niri.connectionState = "connecting"
        niriSocket.connected = true
    }

    function onLinkUp() {
        niri.connected = true
        niri.connectionState = "connected"
        niri._retryMs = Settings.niriRetryMinMs

        // Request the event stream: complete state up-front,
        // then incremental updates. One line, JSON bare string.
        niriSocket.write('"EventStream"\n')
        niriSocket.flush()

        console.info(`[KAIROS] niri: linked`)
    }

    function onLinkLost(reason) {
        if (!niri.connected && niri.connectionState !== "connecting") {
            return
        }

        niri.connected = false
        niri.connectionState = "disconnected"

        console.warn(`[KAIROS] niri: link lost (${reason}), retrying`)
        niri.scheduleRetry()
    }

    function scheduleRetry() {
        retryTimer.interval = niri._retryMs
        niri._retryMs = Math.min(niri._retryMs * 2, Settings.niriRetryMaxMs)
        retryTimer.start()
    }

    // ─────────────────────────────────────────────
    // EVENT PARSING
    // Each line is one JSON value. Unwrap a possible
    // Ok/Err envelope, then dispatch on the variant name.
    // ─────────────────────────────────────────────

    function handleLine(data) {
        const line = data.trim()

        if (line === "") {
            return
        }

        let obj

        try {
            obj = JSON.parse(line)
        } catch (error) {
            return
        }

        if (obj === null || typeof obj !== "object") {
            return
        }

        if ("Ok" in obj) {
            obj = obj.Ok
        } else if ("Err" in obj) {
            return
        }

        if (obj === null || typeof obj !== "object") {
            return
        }

        const keys = Object.keys(obj)

        if (keys.length !== 1) {
            return
        }

        const key = keys[0]
        const payload = obj[key]

        switch (key) {
        case "ConfigLoaded":
            // Always first; acknowledges the connection. No state.
            break
        case "WorkspacesChanged":
            niri.rebuildWorkspaces(payload.workspaces)
            break
        case "WorkspaceActivated":
            niri.workspaceActivated(payload.id, payload.focused)
            niri.markWorkspaceFocused(payload.id, payload.focused)
            break
        case "WindowsChanged":
            niri.rebuildWindows(payload.windows)
            break
        case "WindowOpenedOrChanged":
            niri.upsertWindow(payload.window)
            break
        case "WindowClosed":
            niri.removeWindow(payload.id)
            break
        case "WindowFocusChanged":
            niri.setFocusedWindow(payload.id)
            break
        default:
            // Urgency / layouts / keyboard / casts ... ignored in v0.3.
            break
        }
    }

    // ─────────────────────────────────────────────
    // MODEL BUILDS (full-replacement events)
    // ─────────────────────────────────────────────

    function rebuildWorkspaces(list) {
        const built = []

        for (const raw of list) {
            built.push(niri.buildWorkspace(raw))
        }

        niri.workspaces = built
        niri.refreshDerived()
    }

    function buildWorkspace(raw) {
        return {
            id: Number(raw.id),
            name: raw.name !== null ? raw.name : null,
            idx: raw.idx !== null && raw.idx !== undefined ? Number(raw.idx) : 0,
            output: raw.output !== null ? raw.output : "",
            isFocused: !!raw.is_focused,
            isActive: !!raw.is_active,
            urgent: !!raw.is_urgent,
            activeWindowId: raw.active_window_id !== null ? Number(raw.active_window_id) : null,
            windowCount: 0
        }
    }

    // Optimistic focus move. WorkspacesChanged (authoritative)
    // follows immediately and reconciles any skew.
    function markWorkspaceFocused(id, focused) {
        if (!focused) {
            return
        }

        const updated = []

        for (const w of niri.workspaces) {
            updated.push(niri.cloneWorkspace(w, w.id === id))
        }

        niri.workspaces = updated
        niri.refreshDerived()
    }

    function cloneWorkspace(w, isFocused) {
        return {
            id: w.id,
            name: w.name,
            idx: w.idx,
            output: w.output,
            isFocused: isFocused,
            isActive: w.isActive,
            urgent: w.urgent,
            activeWindowId: w.activeWindowId,
            windowCount: w.windowCount
        }
    }

    function rebuildWindows(list) {
        const built = []

        for (const raw of list) {
            built.push(niri.buildWindow(raw))
        }

        niri.windows = built
        niri.refreshDerived()
    }

    function buildWindow(raw) {
        return {
            id: Number(raw.id),
            title: raw.title !== null ? raw.title : "",
            appId: raw.app_id !== null ? raw.app_id : "",
            workspaceId: raw.workspace_id !== null ? Number(raw.workspace_id) : null,
            isFocused: !!raw.is_focused
        }
    }

    function upsertWindow(window) {
        const w = niri.buildWindow(window)
        const kept = []

        for (const old of niri.windows) {
            if (old.id !== w.id) {
                kept.push(old)
            }
        }

        kept.push(w)
        niri.windows = kept
        niri.refreshDerived()
    }

    function removeWindow(id) {
        const kept = []

        for (const w of niri.windows) {
            if (w.id !== id) {
                kept.push(w)
            }
        }

        niri.windows = kept
        niri.refreshDerived()
    }

    function setFocusedWindow(id) {
        const focused = []

        for (const w of niri.windows) {
            focused.push(niri.cloneWindow(w, w.id === id))
        }

        niri.windows = focused
        niri.refreshDerived()
    }

    function cloneWindow(w, isFocused) {
        return {
            id: w.id,
            title: w.title,
            appId: w.appId,
            workspaceId: w.workspaceId,
            isFocused: isFocused
        }
    }

    // ─────────────────────────────────────────────
    // DERIVED STATE
    // ─────────────────────────────────────────────

    function refreshDerived() {
        const ws = niri.workspaces
        const wsWindows = niri.windows

        const out = []

        for (const w of ws) {
            if (w.output !== "" && out.indexOf(w.output) < 0) {
                out.push(w.output)
            }
        }
        niri.outputs = out

        niri.activeWorkspaces = niri.filterBy(ws, "isActive")

        niri.focusedWorkspace = niri.firstBy(ws, "isFocused")
        niri.activeWorkspace = niri.focusedWorkspace !== null
            ? niri.focusedWorkspace
            : niri.firstBy(ws, "isActive")

        const counts = {}

        for (const win of wsWindows) {
            if (win.workspaceId !== null) {
                counts[win.workspaceId] = (counts[win.workspaceId] || 0) + 1
            }
        }

        for (const w of ws) {
            w.windowCount = counts[w.id] || 0
        }

        niri.focusedWindow = niri.firstBy(wsWindows, "isFocused")
    }

    function firstBy(list, field) {
        for (const item of list) {
            if (item[field]) {
                return item
            }
        }

        return null
    }

    function filterBy(list, field) {
        const out = []

        for (const item of list) {
            if (item[field]) {
                out.push(item)
            }
        }

        return out
    }

    // ─────────────────────────────────────────────
    // VIEW HELPERS
    // ─────────────────────────────────────────────

    // Workspaces belonging to one output, ordered by idx.
    function workspacesFor(output) {
        const out = niri.workspaces.filter(function (w) {
            return w.output === output
        })

        out.sort(function (a, b) {
            return a.idx - b.idx
        })

        return out
    }

    // 0-based index of the display workspace for an output:
    // the focused one if we have it, else this output's active.
    function displayIndexFor(output) {
        const mine = niri.workspacesFor(output)

        let target = null

        for (const w of mine) {
            if (w.isFocused) {
                target = w
                break
            }
        }

        if (target === null) {
            for (const w of mine) {
                if (w.isActive) {
                    target = w
                    break
                }
            }
        }

        return target !== null ? target.idx : -1
    }

    property int _retryMs: Settings.niriRetryMinMs
    property bool _wasConnected: false

    Component.onCompleted: tryConnect()
}