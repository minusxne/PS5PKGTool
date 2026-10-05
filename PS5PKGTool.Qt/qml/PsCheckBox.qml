import QtQuick
import QtQuick.Controls.Basic

CheckBox {
    id: control
    hoverEnabled: true
    spacing: 10
    indicator: Rectangle {
        implicitWidth: 20
        implicitHeight: 20
        x: control.leftPadding
        y: (control.height - height) / 2
        radius: 5
        color: control.checked ? Theme.accent : "transparent"
        border.width: control.visualFocus ? 2 : 1.5
        border.color: control.visualFocus ? Theme.focus : control.checked ? Theme.accent : Theme.outlineStrong
        Icon { anchors.centerIn: parent; name: "check"; size: 14; visible: control.checked }
    }
    contentItem: Text {
        leftPadding: control.indicator.width + control.spacing
        text: control.text
        color: control.enabled ? Theme.text : Theme.textFaint
        font.pixelSize: Theme.fontBody
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
    }
}
