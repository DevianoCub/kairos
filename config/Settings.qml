pragma Singleton

import QtQuick

QtObject {
    id: settings

    // ─────────────────────────────────────────────
    // KAIROS RUNTIME SETTINGS
    //
    // User-facing behavior knobs. Values here live
    // outside the visual theme so behavior can be
    // adjusted without touching palette tokens.
    // ─────────────────────────────────────────────

    // Overlay HUD height in logical pixels.
    readonly property int hudHeight: 42

    // System metric refresh interval (ms).
    // 1000 = clock/cpu/ram cadence, matching v0.1.
    readonly property int refreshMs: 1000

    // Clock rendering. Empty format disables the value.
    readonly property string clockFormat: "HH:mm:ss"
    readonly property string dateFormat: "dd/MM/yyyy"
    readonly property bool showDate: false

    // The HUD is the real desktop panel: it reserves its
    // top exclusion zone so application windows work
    // around it. (layer-shell exclusive zone > 0 = push
    // windows down below the HUD; 0 = pure overlay.)
    readonly property int exclusiveZone: settings.hudHeight

    // Update intervals (ms). Higher-frequency metrics
    // may slot in at these cadences later.
    readonly property int fastInterval: 1000
    readonly property int slowInterval: 5000

    // Telemetry rendering.
    readonly property int graphSamples: 48
    readonly property int gaugeSegments: 24

    // Niri backend (v0.3): connection retry cadence.
    readonly property int niriRetryMinMs: 1000
    readonly property int niriRetryMaxMs: 10000
    readonly property int niriRetryIdleMs: 5000

    // Bottom contextual rail (v0.4).
    readonly property bool railHoverReveal: true
    readonly property int railStripHeight: 12
    readonly property int railHeight: 36
    readonly property int railRevealMs: 3000
    readonly property int railHoverGraceMs: 1200

    // Command center / app launcher (v0.5).
    //
    // The launcher is an opaque command panel: a stable dark surface that
    // isolates the list from whatever wallpaper sits behind it. launcherMaxWidth
    // is the panel width, launcherCenterShiftY the elevation of its center
    // above true screen center, launcherPanelPadding the inner margin of the
    // surface. The result list breathes when few rows are shown and compacts
    // into a tight stack for many.
    readonly property int launcherMaxWidth: 420
    readonly property int launcherCenterShiftY: 42
    readonly property int launcherPanelPadding: 14
    readonly property int launcherHeaderGap: 6
    readonly property int launcherInputGap: 12
    readonly property int launcherDividerGap: 8
    readonly property int launcherMaxResults: 8
    readonly property int launcherResultHeight: 26
    readonly property int launcherNodeGapLoose: 14
    readonly property int launcherNodeGapCompact: 5
    readonly property int launcherPromptWidth: 240
}