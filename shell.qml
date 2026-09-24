import Quickshell
import QtQuick
import "services"
import "panels"
import "config"

// ─────────────────────────────────────────────
// KAIROS — FICTIONAL-SYSTEM DESKTOP SHELL
//
// v0.3
//
// Composition root only. Owns the service layer and
// instantiates one TopHud + one WorkspacePanel per
// connected screen. No data acquisition or styling
// decisions live here.
//
// Run:    qs -c kairos
// ─────────────────────────────────────────────

ShellRoot {
    id: root

    // Service layer (data → state). One instance shared
    // by every screen; panels bind, never probe.
    property SystemService systemService: SystemService {}
    property NiriService niriService: NiriService {}

    // Per-screen overlay HUD.
    Variants {
        model: Quickshell.screens

        TopHud {
            screen: modelData
            systemService: root.systemService
            niriService: root.niriService
        }
    }

    // Per-screen workspace matrix (v0.3). Hidden when the
    // Niri link is down — can't be seen, never faked.
    Variants {
        model: Quickshell.screens

        WorkspacePanel {
            visible: Settings.showWorkspacePanel
            screen: modelData
            niriService: root.niriService
        }
    }

    Component.onCompleted: {
        console.info(`[KAIROS] v0.3 online — ${root.systemService.compositorName} compositor`)
    }
}