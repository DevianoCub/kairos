import QtQuick
import QtQuick.Layouts
import ".."
import "../../config"

// ─────────────────────────────────────────────
// KAIROS LAUNCHER RESULT ROW (v0.5)
//
// One search result. Compact, monochrome, no icon:
// name (primary), generic name (secondary), first
// category as a micro right-aligned tag. Selection
// is a surfaceAlt backing plus a 2px accent bar —
// the same restrained instrument language as the
// HUD / rail. The row requests selection on hover
// and activation on click; keyboard selection is
// owned by the Launcher.
// ─────────────────────────────────────────────

Item {
    id: rrow
    implicitWidth: 160

    property var result: null
    property bool selected: false
    property int rowHeight: 26

    signal requestSelect()
    signal activate()

    height: rrow.rowHeight

    readonly property string categoryTag: {
        const r = rrow.result
        if (r !== null && r !== undefined && r.categories && r.categories.length > 0) {
            return String(r.categories[0]).toUpperCase()
        }
        return ""
    }

    // Selection backing.
    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Theme.surfaceAlt
        opacity: rrow.selected ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.reducedMotion ? 0 : Theme.animationFast
                easing.type: Theme.easing
            }
        }
    }

    // Selected accent bar.
    Rectangle {
        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
        }
        width: 2
        height: 12
        color: rrow.selected ? Theme.accent : "transparent"
    }

    RowLayout {
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 14
            rightMargin: 14
        }
        spacing: 10

        HudText {
            text: rrow.result !== null ? rrow.result.name : ""
            color: rrow.selected ? Theme.textBright : Theme.text
            font.pixelSize: Theme.sizeValue
            font.bold: rrow.selected
            Layout.alignment: Qt.AlignVCenter
            elide: Text.ElideRight
        }

        HudText {
            visible: rrow.result !== null
                && rrow.result.genericName !== undefined
                && rrow.result.genericName !== ""
            text: rrow.result.genericName
            color: Theme.muted
            font.pixelSize: Theme.sizeMicro
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 150
            Layout.maximumWidth: 150
            elide: Text.ElideRight
        }

        Item {
            Layout.fillWidth: true
        }

        HudText {
            visible: rrow.categoryTag !== ""
            text: rrow.categoryTag
            color: Theme.subtle
            font.pixelSize: Theme.sizeMicro
            font.letterSpacing: Theme.trackMicro
            Layout.alignment: Qt.AlignVCenter
        }
    }

    // Pointer hover moves the selection; click activates.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: rrow.requestSelect()
        onClicked: rrow.activate()
    }
}