import QtQuick
import "../config"

// Base technical text primitive.
// All KAIROS text derives from this so typography
// stays centralized in one place.
Text {
    id: hudText

    color: Theme.text
    font.family: Theme.fontMono
    font.pixelSize: Theme.sizeValue
    font.bold: false
    verticalAlignment: Text.AlignVCenter
    renderType: Text.QtRendering
}