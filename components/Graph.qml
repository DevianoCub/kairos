import QtQuick
import "../config"

// Right-aligned bar-history sparkline. Takes a plain JS
// array of numbers (push on the latest edge, oldest at 0).
//
// maxValue sets a fixed ceiling (0..100 for percent series);
// set maxValue: 0 to self-scale to the series peak (rates).
//
// Usage:
//     Graph {
//         samples: SystemService.cpuHistory
//         Layout.preferredWidth: 72
//         Layout.preferredHeight: 12
//     }
Item {
    id: graph

    property variant samples: []
    property color color: Theme.accent
    property real maxValue: 100
    property int barSpacing: 1

    implicitWidth: samples.length * 3
    implicitHeight: 14

    readonly property real peak: {
        let high = graph.maxValue

        for (const value of graph.samples) {
            high = Math.max(high, Number(value) || 0)
        }

        return high > 0 ? high : 1
    }

    Repeater {
        model: graph.samples

        delegate: Rectangle {
            readonly property real raw: Number(modelData) || 0
            readonly property int count: graph.samples.length
            readonly property real cellWidth: Math.max(
                1,
                Math.floor((graph.width - graph.barSpacing * (Math.max(1, count) - 1)) / Math.max(1, count))
            )

            width: Math.min(cellWidth, graph.width)
            height: Math.max(1, Math.round(graph.height * Math.min(1, raw / graph.peak)))
            x: index * (cellWidth + graph.barSpacing)
            y: graph.height - height
            color: graph.color
            opacity: 0.85
        }
    }
}