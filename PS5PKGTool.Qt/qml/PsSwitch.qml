import QtQuick
import QtQuick.Controls.Basic

// A settings row switch with a label and optional description.
Switch {
    id: control
    property string description: ""

    // An explicit implicit width keeps the wrapped label (sized from the switch's width) from
    // feeding back into the layout that sizes the switch.
    implicitWidth: 360
    implicitHeight: Math.max(48, label.implicitHeight + 16)
    hoverEnabled: true

    indicator: Rectangle {
        implicitWidth: 46
        implicitHeight: 26
        x: control.width - width - control.rightPadding
        y: (control.height - height) / 2
        radius: 13
        color: control.checked ? Theme.accent : Qt.rgba(1, 1, 1, 0.16)
        border.width: control.visualFocus ? 2 : 0
        border.color: Theme.focus
        Behavior on color { ColorAnimation { duration: Theme.fast } }
        Rectangle {
            x: control.checked ? parent.width - width - 3 : 3
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            height: 20
            radius: 10
            color: "white"
            Behavior on x { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } }
        }
    }
    contentItem: Column {
        id: label
        rightPadding: 60
        spacing: 2
        anchors.verticalCenter: parent.verticalCenter
        Text { text: control.text; color: Theme.text; font.pixelSize: Theme.fontBody; width: control.width - 70; wrapMode: Text.WordWrap }
        Text { visible: control.description.length > 0; text: control.description; color: Theme.textFaint; font.pixelSize: Theme.fontSmall; width: control.width - 70; wrapMode: Text.WordWrap }
    }
}
