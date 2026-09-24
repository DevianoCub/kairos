import QtQuick
import "../config"

// Small status indicator dot with state color.
// State maps to a themed color; animates color/opacity
// changes so state transitions read as mechanical events.
//
// Status codes: "ok" | "warn" | "critical" | "off" | "unknown"
Item {
    id: statusLight

    property alias statusColor: light.color
    property string status: "ok"
    property int dotSize: 6

    implicitWidth: dotSize
    implicitHeight: dotSize

    Rectangle {
        id: light
        anchors.centerIn: parent
        width: statusLight.dotSize
        height: statusLight.dotSize
        radius: width / 2

        color: {
            switch (statusLight.status) {
            case "ok": return Theme.ok
            case "warn": return Theme.warning
            case "critical": return Theme.critical
            case "off": return Theme.subtle
            default: return Theme.accent
            }
        }

        opacity: statusLight.status === "off" ? 0.35 : 1.0

        Behavior on color {
            ColorAnimation {
                duration: Theme.reducedMotion ? 0 : Theme.animationFast
                easing.type: Easing.OutCubic
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.reducedMotion ? 0 : Theme.animationFast
                easing.type: Easing.OutCubic
            }
        }
    }
}