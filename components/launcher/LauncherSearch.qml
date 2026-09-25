import QtQuick
import QtQuick.Layouts
import ".."
import "../../config"

// ─────────────────────────────────────────────
// KAIROS LAUNCHER SEARCH FIELD (v0.5)
//
// Dumb command-input line. It converts keystrokes
// to a query text change and elevates the
// navigation keys as signals; it NEVER owns the
// query, the selection or the lifecycle. The
// Launcher owns all three.
// ─────────────────────────────────────────────

Item {
    id: search
    height: 24

    // Navigation / action requests (decided upstream).
    signal navUp()
    signal navDown()
    signal submit()
    signal dismiss()
    // The user's text changed. Pass-through, not state.
    signal queryTextChanged(string text)

    // Programmatic access used by the Launcher.
    function setQuery(t) { input.text = t }
    function currentText() { return input.text }
    // Pixel width of the typed command (drives the nucleus baseline).
    function promptPixelWidth() { return input.contentWidth }
    function forceFocus() { input.forceActiveFocus() }
    function releaseFocus() {
        input.focus = false
        Qt.inputMethod.hide()
    }

    RowLayout {
        anchors.fill: parent
        spacing: 10

        HudText {
            text: ">"
            color: Theme.accent
            font.pixelSize: Theme.sizeValue
            font.bold: true
            Layout.alignment: Qt.AlignVCenter
        }

        TextInput {
            id: input
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter

            text: ""
            color: Theme.textBright
            selectionColor: Theme.raised
            selectedTextColor: Theme.textBright
            cursorVisible: true
            clip: true
            selectByMouse: true

            font.family: Theme.fontMono
            font.pixelSize: Theme.sizeValue

            // Keyboard-first: no predictive text surface.
            inputMethodHints: Qt.ImhNoPredictiveText

            onTextChanged: search.queryTextChanged(input.text)

            Keys.onUpPressed: {
                event.accepted = true
                search.navUp()
            }
            Keys.onDownPressed: {
                event.accepted = true
                search.navDown()
            }
            Keys.onReturnPressed: {
                event.accepted = true
                search.submit()
            }
            Keys.onEnterPressed: {
                event.accepted = true
                search.submit()
            }
            Keys.onEscapePressed: {
                event.accepted = true
                search.dismiss()
            }
        }
    }
}