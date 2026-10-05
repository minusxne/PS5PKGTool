import QtQuick
import QtQuick.Controls.Basic

SpinBox {
    id: control
    implicitHeight: 42
    implicitWidth: 150
    editable: true
    font.pixelSize: Theme.fontBody

    contentItem: TextInput {
        text: control.displayText
        font: control.font
        color: Theme.text
        selectionColor: Theme.accent
        horizontalAlignment: Qt.AlignHCenter
        verticalAlignment: Qt.AlignVCenter
        readOnly: !control.editable
        validator: control.validator
        inputMethodHints: Qt.ImhFormattedNumbersOnly
    }
    up.indicator: Rectangle {
        x: control.width - width - 4
        y: 4
        width: 34
        height: control.height - 8
        radius: 8
        color: control.up.pressed ? Theme.surfacePressed : control.up.hovered ? Theme.surfaceHover : "transparent"
        Icon { anchors.centerIn: parent; name: "add"; size: 16 }
    }
    down.indicator: Rectangle {
        x: 4
        y: 4
        width: 34
        height: control.height - 8
        radius: 8
        color: control.down.pressed ? Theme.surfacePressed : control.down.hovered ? Theme.surfaceHover : "transparent"
        Rectangle { anchors.centerIn: parent; width: 12; height: 2; radius: 1; color: "white" }
    }
    background: Rectangle {
        radius: Theme.radiusSmall + 2
        color: Qt.rgba(1, 1, 1, 0.07)
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? Theme.accentBright : Theme.outline
    }
}
