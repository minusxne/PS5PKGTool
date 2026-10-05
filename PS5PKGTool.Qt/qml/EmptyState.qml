import QtQuick
import QtQuick.Layouts

// Centered icon, title, explanation and optional actions for empty views.
ColumnLayout {
    id: root
    property string icon: "info"
    property string title: ""
    property string text: ""
    default property alias actions: actionRow.data
    spacing: 12

    Rectangle {
        Layout.alignment: Qt.AlignHCenter
        width: 84; height: 84; radius: 42
        color: Qt.rgba(1, 1, 1, 0.07)
        Icon { anchors.centerIn: parent; name: root.icon; size: 38; opacity: 0.85 }
    }
    Text {
        Layout.alignment: Qt.AlignHCenter
        text: root.title
        color: Theme.text
        font.pixelSize: Theme.fontTitle - 4
        font.weight: Font.DemiBold
    }
    Text {
        Layout.alignment: Qt.AlignHCenter
        Layout.maximumWidth: 520
        text: root.text
        visible: text.length > 0
        color: Theme.textDim
        font.pixelSize: Theme.fontBody
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
    }
    Row {
        id: actionRow
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 8
        spacing: 10
    }
}
