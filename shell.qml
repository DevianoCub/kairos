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
// TopHud, plus the GLOBAL contextual active-window
// layer (one BottomRail + one FocusCapsule, driven
// by a single FocusPulse).
//
// The contextual layer is deliberately singular:
// compositor state is global and the presentation
// is global too — exactly one rail and one
// capsule, never per-output copies. They follow
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
    // CONTEXTUAL ACTIVE-WINDOW LAYER (v0.4)
    //
    // GLOBAL, not per-output. One FocusPulse turns
    // common compositor state into a deduplicated
    // attention signal; one BottomRail and one
    // FocusCapsule render it. Both panel windows
    // bind their `screen` to the focused workspace's
    // output, so the single surface follows the
    // user instead of being duplicated.
    // ─────────────────────────────────────────

    FocusPulse {
        id: fb
        compositor: root.compositor
    }

    BottomRail {
        systemService: root.systemService
        fb: fb
    }

    FocusCapsule {
        fb: fb
    }

    Component.onCompleted: {
        console.info(`[KAIROS] v0.4 online — ${root.systemService.compositorName} compositor`)
    }
}