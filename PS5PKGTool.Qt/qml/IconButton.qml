import QtQuick
import QtQuick.Controls.Basic

// Round icon-only button with a tooltip.
ToolButton {
    id: control
    property string iconName: ""
    property string tip: ""
    property int size: 40
    property bool active: false
    property color tint: "white"

    implicitWidth: size
    implicitHeight: size
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : 0.35

    ToolTip.visible: hovered && tip.length > 0
    ToolTip.text: tip
    ToolTip.delay: 450

    contentItem: Item {
        Icon {
            anchors.centerIn: parent
            name: control.iconName
            size: Math.round(control.size * 0.5)
            color: control.tint
        }
    }
    background: Rectangle {
        radius: width / 2
        color: control.active ? Qt.rgba(1, 1, 1, 0.18) : control.pressed ? Theme.surfacePressed : control.hovered ? Theme.surfaceHover : "transparent"
        border.width: control.visualFocus ? 2 : 0
        border.color: Theme.focus
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }
}
