import Quickshell
import QtQuick
import "services"
import "services/compositor"
import "panels"
import "components"
import "config"

// ─────────────────────────────────────────────
// KAIROS — FICTIONAL-SYSTEM DESKTOP SHELL
//
// v0.4
//
// Composition root only. Owns the service layer
// and instantiates the panels: the per-screen
// HUD, plus the GLOBAL contextual bottom rail
// driven by a single FocusPulse.
//
// The contextual surface is deliberately singular:
// compositor state is global and the presentation
// is global too — exactly one rail surface on the
// bottom edge, never per-output copies. It follows
// the focused workspace's screen.
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
    //
    // GLOBAL, not per-output. One FocusPulse turns
    // common compositor state into a deduplicated
    // attention signal; one BottomRail renders it.
    // The rail binds its `screen` to the focused
    // workspace's output, so the single surface
    // follows the user instead of being duplicated.
    // ─────────────────────────────────────────

    FocusPulse {
        id: fb
        compositor: root.compositor
    }

    BottomRail {
        fb: fb
    }

    Component.onCompleted: {
        console.info(`[KAIROS] v0.4 online — ${root.systemService.compositorName} compositor`)
    }
}