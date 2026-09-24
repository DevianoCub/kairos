import QtQuick
import "../config"

// Segmented meter for 0..100 metrics (CPU%, MEM, ...).
//
// Usage:
//     Gauge {
//         value: SystemService.cpuPercentValue
//         Layout.preferredWidth: 56
//     }
Item {
    id: gauge

    property real value: 0
    property color color: Theme.accent
    property color trackColor: Theme.lineSoft
    property int segments: Settings.gaugeSegments

    implicitWidth: segments * 3
    implicitHeight: 10

    readonly property real fill: Math.min(1, Math.max(0, value / 100))
    readonly property real cellWidth: Math.max(1, Math.floor((width - (segments - 1)) / segments))

    Repeater {
        model: gauge.segments

        delegate: Rectangle {
            readonly property bool lit: index < Math.round(gauge.fill * gauge.segments)

            width: gauge.cellWidth
            height: gauge.height
            x: index * (gauge.cellWidth + 1)
            y: 0
            radius: width > 2 ? 1 : 0
            color: lit ? gauge.color : gauge.trackColor
            opacity: lit ? 0.95 : 0.5
        }
    }
}