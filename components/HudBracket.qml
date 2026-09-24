import QtQuick
import "../config"

// Corner / edge bracket marking for HUD regions.
// Renders one of the four box-drawing corner glyphs.
//
// Usage:
//     HudBracket { corner: "topLeft" }
HudText {
    id: hudBracket

    property string corner: "topLeft"
    property color markColor: Theme.subtle

    text: {
        switch (corner) {
        case "topLeft": return "┌"
        case "topRight": return "┐"
        case "bottomLeft": return "└"
        case "bottomRight": return "┘"
        default: return "┌"
        }
    }

    color: markColor
    font.pixelSize: Theme.sizeLabel
    font.bold: false
    font.letterSpacing: 0
}