import QtQuick
import Quickshell
import Quickshell.Io
import "."
import "../../config"

// ─────────────────────────────────────────────
// KAIROS NIRI BACKEND (v0.3.1)
//
// Read-only bridge to the Niri compositor IPC,
// implementing the common CompositorService contract.
//
// Protocol (niri ≥ 26):
//   connect  →  write a bare string `"EventStream"`\n
//               over the raw NIRI_SOCKET. The compositor
//               answers with an initial full-state burst,
//               then pushes incremental events. All lines
//               are newline-delimited JSON.
//   events   →  WorkspacesChanged / WindowsChanged are
//               authoritative full replacements.
//               WorkspaceActivated {id, focused} drives
//               optimistic focus moves; the authoritative
//               WorkspacesChanged follows immediately.
//               WindowOpenedOrChanged / WindowClosed /
//               WindowFocusChanged patch window state.
//   failure  →  connected = false, states reconnecting/
//               error, exponential-backoff retry. No
//               workspace data is ever fabricated.
//
// Never issues commands to Niri in this milestone.
//
// Exposed (via the base contract):
//   name="Niri", connected, connectionState, workspaces,
//   activeWorkspaces, focusedWorkspace, activeWorkspace,
//   windows, focusedWindow, outputs, workspacesFor(...),
//   displayColumnFor(...), displayIndexFor(...)
// ─────────────────────────────────────────────

CompositorService {
    id: niri

    // ─────────────────────────────────────────────
    // CONNECTION (Niri-specific details stay here)
    // ─────────────────────────────────────────────

    readonly property string socketPath: Quickshell.env("NIRI_SOCKET")

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

    Timer {
        id: idleTimer
        interval: Settings.niriRetryIdleMs

        onTriggered: niri.tryConnect()
    }

    // ─────────────────────────────────────────────
    // LIFECYCLE
    //   disconnected   initial / idle
    //   connecting     socket connect attempt
    //   connected      event stream live
    //   reconnecting   was connected, link dropped
    //   error          connect attempt failed
    //   unsupported    no NIRI_SOCKET (not Niri)
    // ─────────────────────────────────────────────

    function tryConnect() {
        if (niri.connected || niriSocket.connected) {
            return
        }

        const path = niri.socketPath

        if (path === "") {
            niri.connected = false
            niri.connectionState = "unsupported"
            idleTimer.start()
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

        // Request the event stream: full state up-front,
        // then incremental updates. One line, bare string.
        niriSocket.write('"EventStream"\n')
        niriSocket.flush()

        console.info(`[KAIROS] niri: linked`)
    }

    function onLinkLost(reason) {
        if (!niri.connected && niri.connectionState !== "connecting") {
            return
        }

        const wasUp = niri.connectionState === "connected"

        niri.connected = false
        niri.connectionState = wasUp ? "reconnecting" : "error"

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

        // A malformed payload must not kill the event stream;
        // drop one event, keep the link.
        try {
            switch (key) {
            case "ConfigLoaded":
                // Acknowledges the connection. No state.
                break
            case "WorkspacesChanged":
                niri.rebuildWorkspaces(payload.workspaces)
                break
            case "WorkspaceActivated":
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
                // Everything else is ignored in v0.3.1.
                break
            }
        } catch (error) {
            console.warn(`[KAIROS] niri: dropped event (${error})`)
        }
    }

    // ─────────────────────────────────────────────
    // MODEL BUILDS (full-replacement events)
    // Common shape: { id, index, name, output, isActive,
    //                 isFocused, isUrgent, occupied }
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
            index: raw.idx !== null && raw.idx !== undefined ? Number(raw.idx) : 0,
            name: raw.name !== null ? raw.name : null,
            output: raw.output !== null ? raw.output : "",
            isActive: !!raw.is_active,
            isFocused: !!raw.is_focused,
            isUrgent: !!raw.is_urgent,
            occupied: false,
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
            index: w.index,
            name: w.name,
            output: w.output,
            isActive: w.isActive,
            isFocused: isFocused,
            isUrgent: w.isUrgent,
            occupied: w.occupied,
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
            appId: raw.app_id !== null ? raw.app_id : "",
            title: raw.title !== null ? raw.title : "",
            workspaceId: raw.workspace_id !== null ? Number(raw.workspace_id) : null,
            output: "",
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
            appId: w.appId,
            title: w.title,
            workspaceId: w.workspaceId,
            output: w.output,
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

        const outputOf = {}

        for (const w of ws) {
            outputOf[w.id] = w.output
        }

        for (const w of ws) {
            const count = counts[w.id] || 0
            w.windowCount = count
            w.occupied = count > 0
        }

        for (const win of wsWindows) {
            win.output = win.workspaceId !== null
                ? (outputOf[win.workspaceId] !== undefined ? outputOf[win.workspaceId] : "")
                : ""
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

    property int _retryMs: Settings.niriRetryMinMs
    property bool _wasConnected: false

    Component.onCompleted: {
        niri.name = "Niri"
        niri.tryConnect()
    }
}