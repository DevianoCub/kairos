import Quickshell
import Quickshell.Io
import QtQuick
import "services"
import "services/compositor"
import "services/commands"
import "panels"
import "components"
import "config"

// ─────────────────────────────────────────────
// KAIROS — FICTIONAL-SYSTEM DESKTOP SHELL
//
// v0.5
//
// Composition root only. Owns the service layer
// and instantiates the panels: the per-screen
// HUD, plus the GLOBAL contextual bottom rail
// driven by a single FocusPulse, plus spawning
// the EPHEMERAL command-center launcher as a
// separate single-window process.
//
// Surfaces (layer-shell), counted by the
// compositor while KAIROS is idle:
//   1. TopHud        permanent, per-output,
//                    exclusive top zone
//   2. BottomRail    permanent, global overlay,
//                    zero exclusion zone
// The app launcher (kairos-launcher) adds a THIRD
// layer surface only while open — unmapped when
// CLOSED, zero exclusion zone, existing only
// while typing. It is never a permanent panel and
// never changes any window's work-area geometry.
//
// Services (data → state), one instance each,
// shared by the whole shell; panels bind, never
// probe:
//   systemService   machine telemetry
//   compositor      common compositor seam (Niri)
//   commands        v0.5 command bus (event bus)
//
// The launcher is triggered over Quickshell IPC in
// the process that owns it:
//   qs ipc -c kairos-launcher call kairos-launcher toggle
// (niri keybind not configured in this milestone;
// add `Super+Space` yourself).
//
// The compositor seam (services/compositor/): UI
// panels consume the common CompositorService
// contract. The backend attached here is Niri;
// swapping in another compositor family = one
// changed line, no UI edits.
//
// Run:    qs -c kairos
// ─────────────────────────────────────────────

ShellRoot {
    id: root

    // Service layer (data → state). One instance
    // shared by the whole shell; panels bind, never
    // probe.
    property SystemService systemService: SystemService {}
    property CompositorService compositor: NiriBackend {}
    property var commands: CommandService {}

    // Per-screen overlay HUD.
    Variants {
        model: Quickshell.screens

        TopHud {
            screen: modelData
            systemService: root.systemService
        }
    }

    // ─────────────────────────────────────────
    // CONTEXTUAL ACTIVE-WINDOW SURFACE (v0.4)
    // ─────────────────────────────────────────

    FocusPulse {
        id: fb
        compositor: root.compositor
    }

    BottomRail {
        fb: fb
        commands: root.commands
    }

    // ─────────────────────────────────────────
    // COMMAND CENTER — APP LAUNCHER (v0.5)
    // ─────────────────────────────────────────
    // The launcher runs in its OWN single-window
    // quickshell process (kairos-launcher): niri only
    // forwards exclusive keyboard input to a layer
    // surface that maps as the sole surface of a
    // process. In-process it could never receive
    // typeahead (verified empirically), so this shell
    // simply spawns that process and leaves its IPC
    // handling to its own IpcHandler on the
    // "kairos-launcher" target:
    //   qs ipc -c kairos-launcher call kairos-launcher toggle
    //
    // The spawned process exposes the panel emergency:
    // only if it dies does typeahead vanish; the bind
    // target stays stable.

    property Process launcherProcess: Process {
        command: [
            "quickshell",
            "-p",
            "/home/jupy/.config/quickshell/kairos-launcher"
        ]
        running: true
    }

    Component.onDestruction: {
        launcherProcess.running = false
    }

    Component.onCompleted: {
        console.info(`[KAIROS] v0.5 online — ${root.systemService.compositorName} compositor`)
    }
}