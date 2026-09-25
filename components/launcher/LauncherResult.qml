import QtQuick
import "file:/home/jupy/.config/quickshell/kairos/components"
import "file:/home/jupy/.config/quickshell/kairos/config"

// ─────────────────────────────────────────────
// KAIROS COMMAND PANEL — RESULT ROW (v0.5)
//
// A bare line of type: application name primary,
// first category as a quiet uppercase micro-tag on
// the right. Selection is a thin 2 px accent bar on
// the left edge plus a brighter, bolded name — the
// KAIROS selection state, no cards, no glow.
//
//   │ Firefox                     WEB
//
// Input semantics unchanged: hover selects (on MOVEMENT,
// never the synthetic enter), click activates.
// Backend untouched: this file paints only.
// ─────────────────────────────────────────────

Item {
    id: rnode
    implicitWidth: 200

    property var result: null
    property bool selected: false
    property int rowHeight: 26

    signal requestSelect()
    signal activate()

    height: rnode.rowHeight

    readonly property string categoryTag: {
        const r = rnode.result
        if (r !== null && r !== undefined && r.categories && r.categories.length > 0) {
            return String(r.categories[0]).toUpperCase()
        }
        return ""
    }

    // Selection marker — thin accent bar on the left edge.
    Rectangle {
        id: marker
        x: 0
        y: 0
        width: 2
        height: rnode.height
        color: rnode.selected ? Theme.accent : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: Theme.animationFast
                easing.type: Theme.easing
            }
        }
    }

    // PRIMARY — application name.
    HudText {
        x: 10
        width: Math.max(0, rnode.width - x - 92)
        anchors.verticalCenter: parent.verticalCenter
        text: rnode.result !== null ? rnode.result.name : ""
        color: rnode.selected ? Theme.textBright : Theme.text
        font.pixelSize: Theme.sizeValue
        font.bold: rnode.selected
        elide: Text.ElideRight

        Behavior on color {
            ColorAnimation {
                duration: Theme.animationFast
                easing.type: Theme.easing
            }
        }
    }

    // SECONDARY — first category, quiet right tag.
    HudText {
        anchors {
            right: parent.right
            rightMargin: 4
            verticalCenter: parent.verticalCenter
        }
        visible: rnode.categoryTag !== ""
        text: rnode.categoryTag
        color: Theme.muted
        font.pixelSize: Theme.sizeMicro
        font.letterSpacing: Theme.trackMicro
    }

    // Pointer: hover selects, click activates (same
    // semantics as before — nothing about input changed).
    // Selection is driven by cursor MOVEMENT, not by the
    // synthetic enter that fires when a fresh delegate
    // materializes under a stationary cursor.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: if (containsMouse) rnode.requestSelect()
        onClicked: rnode.activate()
    }
}