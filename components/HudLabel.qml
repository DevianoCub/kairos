import QtQuick
import "../config"

// Micro technical label: small, uppercase, tracked.
// Used for section headers and metric labels.
//
// Usage:
//     HudLabel { caption: "memory" }
HudText {
    id: hudLabel

    property string caption: ""
    property color labelColor: Theme.muted

    text: caption.toUpperCase()
    color: labelColor
    font.pixelSize: Theme.sizeLabel
    font.bold: false
    font.letterSpacing: Theme.trackLabel
}