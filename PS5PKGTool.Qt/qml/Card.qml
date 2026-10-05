import QtQuick

// A translucent rounded panel.
Rectangle {
    property bool raised: false
    radius: Theme.radiusLarge
    color: raised ? Theme.surfaceRaised : Theme.surface
    border.color: Theme.outline
    border.width: 1
}
