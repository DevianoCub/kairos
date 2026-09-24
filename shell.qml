import Quickshell
import QtQuick
import "services"
import "services/compositor"
import "panels"
import "config"

// ─────────────────────────────────────────────
// KAIROS — FICTIONAL-SYSTEM DESKTOP SHELL
//
// v0.3.1
//
// Composition root only. Owns the service layer and
// instantiates one TopHud + one WorkspacePanel per
// connected screen. No data acquisition or styling
// decisions live here.
//
// The compositor seam (services/compositor/): UI panels
// consume the common CompositorService contract. The
// backend attached here is Niri; swapping in another
// compositor family = one changed line, no UI edits.
//
// Run:    qs -c kairos
// ─────────────────────────────────────────────

ShellRoot {
    id: root

    // Service layer (data → state). One instance shared
    // by every screen; panels bind, never probe.
    property SystemService systemService: SystemService {}
    property CompositorService compositor: NiriBackend {}

    // Per-screen overlay HUD.
    Variants {
        model: Quickshell.screens

        TopHud {
            screen: modelData
            systemService: root.systemService
            compositor: root.compositor
        }
    }

    // Per-screen workspace matrix (v0.3+). Never faked:
    // when the desktop backend link is down it renders
    // an honest offline state instead.
    Variants {
        model: Quickshell.screens

        WorkspacePanel {
            visible: Settings.showWorkspacePanel
            screen: modelData
            compositor: root.compositor
        }
    }

    Component.onCompleted: {
        console.info(`[KAIROS] v0.3.1 online — ${root.systemService.compositorName} compositor`)
    }
}