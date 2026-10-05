import QtQuick
import QtQuick.Controls.Basic

TextField {
    id: control
    property string icon: ""
    property bool clearable: false

    implicitHeight: 42
    color: Theme.text
    placeholderTextColor: Theme.textFaint
    selectionColor: Theme.accent
    selectedTextColor: "white"
    font.pixelSize: Theme.fontBody
    leftPadding: icon.length > 0 ? 42 : 14
    rightPadding: clearable && text.length > 0 ? 38 : 14
    verticalAlignment: TextInput.AlignVCenter

    background: Rectangle {
        radius: Theme.radiusSmall + 2
        color: control.activeFocus ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.07)
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? Theme.accentBright : Theme.outline
        Behavior on color { ColorAnimation { duration: Theme.fast } }
        Icon {
            visible: control.icon.length > 0
            name: control.icon
            size: 18
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            opacity: 0.7
        }
        IconButton {
            visible: control.clearable && control.text.length > 0
            iconName: "close"
            size: 28
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            onClicked: control.clear()
        }
    }
}
