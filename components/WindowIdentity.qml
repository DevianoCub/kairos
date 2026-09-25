import QtQuick
import QtQuick.Layouts
import "../config"

// ─────────────────────────────────────────────
// KAIROS WINDOW IDENTITY (v0.4)
//
// Compact window identity row used by the bottom
// rail and (later) the contextual drawer:
//
//   [K] kitty   ~/projects/kairos
//
// Icon = a restrained 17px monogram tile (first
// letter of the app id) so the row is deterministic,
// dependency-free and stays within the KAIROS
// minimal-icon aesthetic. Title elides right.
//
// Consumes the common window descriptor from
// CompositorService only.
// ─────────────────────────────────────────────

RowLayout {
    id: ident

    property var window: null
    property int titleWidth: 120

    readonly property string app: {
        const w = ident.window
        if (w === null || w === undefined) return ""
        if (w.appId && w.appId.trim() !== "") return w.appId
        if (w.title && w.title.trim() !== "") return w.title
        return "win"
    }

    readonly property string title: {
        const w = ident.window
        if (w === null || w === undefined) return ""
        const t = w.title ? w.title.trim() : ""
        if (t !== "") return t
        return ""
    }

    spacing: 10

    // ── MONOGRAM TILE ──
    Rectangle {
        Layout.preferredWidth: 17
        Layout.preferredHeight: 17
        Layout.alignment: Qt.AlignVCenter

        color: Theme.surfaceAlt
        border.width: Theme.borderWidth
        border.color: Theme.line

        HudText {
            anchors.centerIn: parent
            text: ident.app.length > 0 ? ident.app.charAt(0).toUpperCase() : "?"
            color: ident.window !== null ? Theme.accent : Theme.subtle
            font.pixelSize: Theme.sizeLabel
            font.bold: true
        }
    }

    // ── APP ID ──
    HudText {
        visible: ident.window !== null
        text: ident.app
        color: Theme.textBright
        font.pixelSize: Theme.sizeValue
        font.bold: true
        Layout.alignment: Qt.AlignVCenter
    }

    // ── TITLE / PATH ──
    HudText {
        visible: ident.window !== null && ident.title !== ""
        text: ident.title
        color: Theme.muted
        font.pixelSize: Theme.sizeMicro
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: ident.titleWidth
        Layout.maximumWidth: ident.titleWidth
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignLeft
    }
}