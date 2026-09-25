import QtQuick
import ".."
import "../../config"

// ─────────────────────────────────────────────
// KAIROS COMMAND NEXUS — RESULT NODE (v0.5)
//
// One search result as a node on the nexus spine.
// Deliberately NOT a menu row and NOT a card: a
// bare line of type with a small MARKER sitting on
// the shared vertical spine (the command bus).
//
//   ────────────────
//     ●  Firefox  WEB
//     ────────────────
//
// The marker is a 1 px tick when unselected and a
// filled 3 px node when SELECTED — the selected
// node also energizes its spine segment (drawn by
// the Launcher) and brightens + bolds its name.
// No icons, no surfaces, no glow: the connection
// IS the emphasis.
//
// Backend untouched: this file paints only.
// ─────────────────────────────────────────────

Item {
    id: rnode
    implicitWidth: 200

    property var result: null
    property bool selected: false
    property int rowHeight: 26

    // The spine's x (column center). The marker parks
    // on it; the name hangs to the right.
    property real spineX: 0
    // Entrance stagger: an index smaller than the
    // Launcher's running threshold is fully in.
    property int rowIndex: 0
    property int enterStage: 0

    signal requestSelect()
    signal activate()

    height: rnode.rowHeight
    opacity: rnode.rowIndex < rnode.enterStage ? 1 : 0

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.animationFast
            easing.type: Theme.easing
        }
    }

    readonly property string categoryTag: {
        const r = rnode.result
        if (r !== null && r !== undefined && r.categories && r.categories.length > 0) {
            return String(r.categories[0]).toUpperCase()
        }
        return ""
    }

    // Selection marker — the node itself.
    Rectangle {
        id: marker
        x: rnode.spineX - width / 2
        y: Math.round((rnode.height - height) / 2)
        width: 3
        height: rnode.selected ? 3 : 1
        color: rnode.selected ? Theme.accent : Theme.accentDim

        Behavior on height {
            NumberAnimation {
                duration: Theme.animationFast
                easing.type: Theme.easing
            }
        }
        Behavior on color {
            NumberAnimation {
                duration: Theme.animationFast
                easing.type: Theme.easing
            }
        }
    }

    // PRIMARY — application name, right of the spine.
    HudText {
        x: rnode.spineX + 14
        width: Math.max(0, rnode.width - (rnode.spineX + 14) - 86)
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

    // TERTIARY — first category, quiet right tag.
    HudText {
        anchors {
            right: parent.right
            rightMargin: 12
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