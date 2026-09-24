import QtQuick

// ─────────────────────────────────────────────
// KAIROS COMMON COMPOSITOR / DESKTOP-STATE
// (v0.3.1)
//
// The single seam between the KAIROS UI and any
// compositor backend. The UI binds ONLY to state
// exposed here. Backends (NiriBackend, ...) fill
// the same contract; a new compositor family is
// added by implementing this contract and swapping
// one instantiation in shell.qml — the UI never
// changes.
//
// Contract:
//   name              "" (no backend) or "Niri", ...
//   connected         backend link is live
//   connectionState   disconnected | connecting |
//                     connected | reconnecting |
//                     error | unsupported
//   workspaces        [{ id, index, name?, output,
//                        isActive, isFocused,
//                        isUrgent, occupied }]
//   activeWorkspaces  active workspaces (per output)
//   focusedWorkspace  focused workspace, or null
//   activeWorkspace   focused, else first active
//   windows           [{ id, appId, title,
//                        workspaceId, output,
//                        isFocused }]
//   focusedWindow     focused window, or null
//   outputs           distinct outputs
//
// Rules:
//   - Backends never fabricate workspace or window
//     data. While the link is down, state is simply
//     NOT updated; the UI renders `connected` /
//     `connectionState` instead.
//   - `index` is the compositor-native numeric index
//     (Niri: 1-based idx). Compositors that name
//     workspaces (Sway, ...) set `name` instead.
//   - Helpers here are compositor-agnostic and
//     operate only on the common state above.
// ─────────────────────────────────────────────

Item {
    id: root
    width: 0
    height: 0
    visible: false

    // Backend identity. "" means KAIROS has no backend
    // for the running compositor.
    property string name: ""

    // Link lifecycle.
    property bool connected: false
    property string connectionState: "disconnected"

    // Common desktop state. Empty until a backend
    // delivers its first full state snapshot.
    property variant workspaces: []
    property variant activeWorkspaces: []
    property variant focusedWorkspace: null
    property variant activeWorkspace: null
    property variant windows: []
    property variant focusedWindow: null
    property variant outputs: []

    // ─────────────────────────────────────────────
    // GENERIC HELPERS (compositor-agnostic)
    // ─────────────────────────────────────────────

    // Workspaces below one output, ordered by index.
    function workspacesFor(output) {
        const out = []

        for (const w of root.workspaces) {
            if (w.output === output) {
                out.push(w)
            }
        }

        out.sort(function (a, b) {
            return a.index - b.index
        })

        return out
    }

    // 0-based column of the display workspace on an
    // output (focused, else active), matching the
    // order of `workspacesFor` — or -1.
    function displayColumnFor(output) {
        const mine = root.workspacesFor(output)

        for (let i = 0; i < mine.length; i++) {
            if (mine[i].isFocused) {
                return i
            }
        }

        for (let i = 0; i < mine.length; i++) {
            if (mine[i].isActive) {
                return i
            }
        }

        return -1
    }

    // Compositor-native index of the workspace the
    // user is looking at on an output — or -1.
    function displayIndexFor(output) {
        const mine = root.workspacesFor(output)

        for (const w of mine) {
            if (w.isFocused) {
                return w.index
            }
        }

        for (const w of mine) {
            if (w.isActive) {
                return w.index
            }
        }

        return -1
    }

    // Short display label for a workspace: its name if
    // the compositor names workspaces, else a zero-
    // padded native index ("01").
    function workspaceLabel(w) {
        if (w === null) {
            return "--"
        }

        if (w.name !== null && w.name !== undefined && w.name !== "") {
            return w.name
        }

        return String(w.index).padStart(2, "0")
    }
}