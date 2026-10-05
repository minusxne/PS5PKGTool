import QtQuick
import QtQuick.Controls.Basic

MenuItem {
    id: control
    property string iconName: ""
    implicitHeight: 38
    implicitWidth: 250
    arrow: Icon {
        x: control.width - width - 10
        y: (control.height - height) / 2
        visible: control.subMenu
        name: "chevron-right"
        size: 14
        opacity: 0.6
    }
    indicator: Item {}
    contentItem: Row {
        spacing: 10
        leftPadding: 4
        Icon {
            name: control.iconName.length > 0 ? control.iconName : control.checked ? "check" : ""
            size: 16
            anchors.verticalCenter: parent.verticalCenter
            opacity: control.enabled ? 0.85 : 0.35
        }
        Text {
            text: control.text
            color: control.enabled ? Theme.text : Theme.textFaint
            font.pixelSize: Theme.fontBody
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            width: control.width - 60
        }
    }
    background: Rectangle {
        radius: 8
        color: control.highlighted ? Theme.accent : "transparent"
    }
}
