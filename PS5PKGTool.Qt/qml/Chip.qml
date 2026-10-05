import QtQuick
import QtQuick.Controls.Basic

// A filter chip: toggles on click; "removable" shows a × that emits removed().
AbstractButton {
    id: control
    property string iconName: ""
    property bool selected: false
    property bool removable: false
    property int count: -1
    signal removed()

    implicitHeight: 32
    implicitWidth: row.implicitWidth + 24
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus

    contentItem: Item {
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 6
            Icon { visible: control.iconName.length > 0; name: control.iconName; size: 15; anchors.verticalCenter: parent.verticalCenter; color: control.selected ? "#0b0e14" : "white" }
            Text {
                text: control.text
                color: control.selected ? "#0b0e14" : Theme.text
                font.pixelSize: Theme.fontSmall + 1
                font.weight: control.selected ? Font.DemiBold : Font.Normal
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: control.count >= 0
                text: control.count
                color: control.selected ? Qt.rgba(0, 0, 0, 0.55) : Theme.textFaint
                font.pixelSize: Theme.fontSmall
                anchors.verticalCenter: parent.verticalCenter
            }
            Icon {
                visible: control.removable
                name: "close"
                size: 13
                color: control.selected ? "#0b0e14" : "white"
                anchors.verticalCenter: parent.verticalCenter
                TapHandler { onTapped: control.removed() }
            }
        }
    }
    background: Rectangle {
        radius: height / 2
        color: control.selected ? "#ffffff" : control.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07)
        border.width: control.visualFocus ? 2 : 1
        border.color: control.visualFocus ? Theme.accentBright : control.selected ? "transparent" : Theme.outline
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }
}
