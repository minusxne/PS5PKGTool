import QtQuick

// A small rounded label, e.g. "Update", "PKG", "Europe".
Rectangle {
    id: root
    property string text: ""
    property color tint: Theme.textDim
    property string icon: ""
    property bool solid: false

    implicitHeight: 24
    implicitWidth: row.implicitWidth + 16
    radius: 6
    color: solid ? tint : Qt.rgba(tint.r, tint.g, tint.b, 0.16)
    border.width: solid ? 0 : 1
    border.color: Qt.rgba(tint.r, tint.g, tint.b, 0.35)

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5
        Icon { visible: root.icon.length > 0; name: root.icon; size: 13; color: root.solid ? "#0b0e14" : root.tint; anchors.verticalCenter: parent.verticalCenter }
        Text {
            text: root.text
            color: root.solid ? "#0b0e14" : Qt.lighter(root.tint, 1.25)
            font.pixelSize: Theme.fontCaption + 1
            font.weight: Font.DemiBold
            font.letterSpacing: 0.3
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
