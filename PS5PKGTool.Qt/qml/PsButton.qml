import QtQuick
import QtQuick.Controls.Basic

// Pill button. "primary" is the white PS5 call-to-action, "accent" the blue one, "ghost" a
// translucent secondary action and "danger" a destructive one.
Button {
    id: control
    property string iconName: ""
    property string variant: "ghost"
    property bool compact: false

    readonly property color fill: variant === "primary" ? "#ffffff"
        : variant === "accent" ? Theme.accent
        : variant === "danger" ? Theme.danger
        : Qt.rgba(1, 1, 1, control.hovered ? 0.16 : 0.10)
    readonly property color ink: variant === "primary" ? "#0b0e14" : "#ffffff"

    implicitHeight: compact ? 34 : 44
    implicitWidth: Math.max(compact ? 34 : 44, contentRow.implicitWidth + (compact ? 24 : 36))
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : 0.4
    scale: control.pressed ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: Theme.fast } }

    contentItem: Item {
        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: 8
            Icon {
                visible: control.iconName.length > 0
                name: control.iconName
                size: control.compact ? 16 : 18
                color: control.ink
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: control.text.length > 0
                text: control.text
                color: control.ink
                font.pixelSize: control.compact ? Theme.fontSmall + 1 : Theme.fontBody
                font.weight: Font.DemiBold
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    background: Rectangle {
        radius: height / 2
        color: control.fill
        Behavior on color { ColorAnimation { duration: Theme.fast } }
        border.width: control.visualFocus ? 2 : 0
        border.color: control.variant === "primary" ? Theme.accentBright : Theme.focus
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "black"
            opacity: control.variant === "primary" && control.hovered ? 0.06 : 0
        }
    }
}
