import QtQuick
import QtQuick.Layouts
import "../config"

// Single label/value instrument used across the HUD.
//
// Usage:
//     Metric {
//         label: "MEM"
//         value: SystemService.memoryPercent
//     }
Row {
    id: metric

    property string label: ""
    property string value: ""
    property color valueColor: Theme.textBright
    property color labelColor: Theme.muted
    property int valuePixelSize: Theme.sizeValue

    spacing: Theme.spacing

    HudLabel {
        anchors.verticalCenter: parent.verticalCenter
        caption: metric.label
        labelColor: metric.labelColor
    }

    HudText {
        anchors.verticalCenter: parent.verticalCenter
        text: metric.value
        color: metric.valueColor
        font.pixelSize: metric.valuePixelSize
        font.bold: true
    }
}