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

    // Whether the HUD reserves screen space below it.
    // 0 keeps KAIROS as a pure overlay. Set > 0 to
    // push windows down (requires compositor layer-shell
    // exclusive zone support).
    readonly property int exclusiveZone: 0

    // Update intervals (ms). Higher-frequency metrics
    // may slot in at these cadences later.
    readonly property int fastInterval: 1000
    readonly property int slowInterval: 5000

    // Telemetry rendering.
    readonly property int graphSamples: 48
    readonly property int gaugeSegments: 24

    // Niri workspace matrix (v0.3).
    readonly property bool showWorkspacePanel: true
    readonly property int wkspPanelOffset: 6
    readonly property int workspacesMaxCells: 12
    readonly property int niriRetryMinMs: 1000
    readonly property int niriRetryMaxMs: 10000
    readonly property int niriRetryIdleMs: 5000
    readonly property int wkspCellWidth: 34
}