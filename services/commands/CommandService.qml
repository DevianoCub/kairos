import QtQuick

// ─────────────────────────────────────────────
// KAIROS COMMAND SERVICE (v0.5)
//
// The command layer seam. The UI never reaches for
// compositor/app/configuration commands directly —
// it publishes intents here and the consuming
// surfaces react. v0.5 implements the FOUNDATION
// only:
//
//   contextualEvent(label)   one-shot contextual
//                            feedback line (bottom
//                            rail consumes it)
//   appLaunched(appName)     the app launcher fired
//
// The command families the milestone deliberately
// does NOT implement yet (volume, brightness,
// notifications, media, bluetooth, wifi, power)
// will attach here when they land — nothing below
// changes when that happens.
//
// Consumed by: BottomRail (contextual feedback).
// Pure bus, no compositor knowledge.
// ─────────────────────────────────────────────

// Non-visual host (zero-size Item so it can own
// child QObjects / Connections); never rendered.
Item {
    id: commands
    width: 0
    height: 0
    visible: false

    // One-shot contextual feedback broadcast.
    signal contextualEvent(string label)

    // The app launcher successfully fired an application.
    signal appLaunched(string appName)

    // Convenience publish with an empty-guard, so
    // callers never emit blank lines.
    function publishContextual(label) {
        if (label !== undefined && label !== null && label.trim() !== "") {
            commands.contextualEvent(label.trim())
        }
    }
}