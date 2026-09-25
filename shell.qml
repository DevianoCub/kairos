import Quickshell
import Quickshell.Io
import QtQuick
import "services"
import "services/compositor"
import "services/commands"
import "panels"
import "components"
import "components/launcher"
import "config"

// ─────────────────────────────────────────────
// KAIROS — FICTIONAL-SYSTEM DESKTOP SHELL
//
// v0.5
//
// Composition root only. Owns the service layer
// and instantiates the panels: the per-screen
// HUD, plus the GLOBAL contextual bottom rail
// driven by a single FocusPulse, plus the
// EPHEMERAL command-center launcher.
//
// Surfaces (layer-shell), counted by the
// compositor while KAIROS is idle:
//   1. TopHud        permanent, per-output,
//                    exclusive top zone
//   2. BottomRail    permanent, global overlay,
//                    zero exclusion zone
//   3. Launcher      EPHEMERAL: unmapped when
//                    CLOSED, zero exclusion zone,
//                    exists only while typing
// The launcher adds a THIRD layer while open —
// it is never a permanent panel and never
// changes any window's work-area geometry.
//
// Services (data → state), one instance each,
// shared by the whole shell; panels bind, never
// probe:
//   systemService   machine telemetry
//   compositor      common compositor seam (Niri)
//   commands        v0.5 command bus (event bus)
//   launcherService app discovery + search + run
//
// The launcher is triggered COMPOSITOR-AGNOSTICALLY
// over Quickshell IPC:
//   qs ipc -c kairos call kairos toggleLauncher
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
    property var launcherService: AppLauncherService {}

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

    Launcher {
        id: launcher
        fb: fb
        service: root.launcherService
        commands: root.commands
    }

    // Compositor-agnostic IPC trigger:
    //   qs ipc -c kairos call kairos toggleLauncher
    // The shell answers on the "kairos" target
    // regardless of backend.
    IpcHandler {
        target: "kairos"
        function toggleLauncher(): void {
            launcher.toggle("ipc")
        }
        // Scripted driving of the exact keyboard code
        // paths (query set / selection / activation), for
        // `qs ipc call` control and verification.
        function launcherQuery(text: string): void {
            launcher.setQueryFromIPC(text)
        }
        function launcherMove(dir: int): void {
            launcher.moveSelection(dir)
        }
        function launcherRun(): void {
            launcher.activateSelection()
        }
    }

    Component.onCompleted: {
        console.info(`[KAIROS] v0.5 online — ${root.systemService.compositorName} compositor`)
    }
}