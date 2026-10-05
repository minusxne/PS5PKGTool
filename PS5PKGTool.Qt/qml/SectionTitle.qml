import QtQuick
import QtQuick.Layouts

RowLayout {
    property alias text: label.text
    property string detail: ""
    spacing: 10
    Text {
        id: label
        color: Theme.text
        font.pixelSize: Theme.fontHeading
        font.weight: Font.DemiBold
    }
    Text {
        text: parent.detail
        visible: text.length > 0
        color: Theme.textFaint
        font.pixelSize: Theme.fontSmall + 1
        Layout.alignment: Qt.AlignBaseline
    }
    Item { Layout.fillWidth: true }
}
