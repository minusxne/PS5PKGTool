import QtQuick
import QtQuick.Layouts

// A compact fact card for the home hero (label, big value, optional detail).
Card {
    id: root
    property string icon: ""
    property string label: ""
    property string value: ""
    property string detail: ""
    property color accent: Theme.accentBright

    implicitWidth: 196
    implicitHeight: 104

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 4
        RowLayout {
            spacing: 8
            Icon { name: root.icon; size: 16; color: root.accent; visible: root.icon.length > 0 }
            Text { text: root.label; color: Theme.textDim; font.pixelSize: Theme.fontSmall; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6 }
        }
        Text {
            Layout.fillWidth: true
            text: root.value.length > 0 ? root.value : "—"
            color: Theme.text
            font.pixelSize: Theme.fontHeading + 1
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Text {
            Layout.fillWidth: true
            text: root.detail
            visible: root.detail.length > 0
            color: Theme.textFaint
            font.pixelSize: Theme.fontSmall
            elide: Text.ElideRight
        }
        Item { Layout.fillHeight: true }
    }
}
