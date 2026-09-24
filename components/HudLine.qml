import QtQuick
import "../config"

// Hairline used for HUD framing and separation.
// Pure geometry: themed 1px line, vertical or horizontal.
Rectangle {
    id: hudLine

    property int orientation: Qt.Horizontal

    implicitWidth: orientation === Qt.Horizontal ? 1 : Theme.borderWidth
    implicitHeight: orientation === Qt.Horizontal ? Theme.borderWidth : 1

    color: Theme.line
    opacity: 1.0
}