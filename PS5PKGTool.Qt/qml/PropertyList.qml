import QtQuick
import QtQuick.Layouts
import PS5PkgTool.Native

// A titled card of label/value rows; clicking a value copies it.
Card {
    id: root
    property string title: ""
    property var rows: []        // [{label, value}]
    implicitHeight: column.implicitHeight + 32

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: 16
        spacing: 2
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 6
            visible: root.title.length > 0
            Text { text: root.title; color: Theme.text; font.pixelSize: Theme.fontBody + 1; font.weight: Font.DemiBold; Layout.fillWidth: true }
            IconButton {
                iconName: "copy"; size: 30; tip: qsTr("Copy all")
                onClicked: App.copy(root.rows.map(function (row) { return row.label + "\t" + row.value }).join("\n"), root.title)
            }
        }
        Repeater {
            model: root.rows
            delegate: Rectangle {
                id: rowItem
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: Math.max(30, value.implicitHeight + 10)
                radius: 6
                color: hover.hovered ? Theme.surfaceHover : "transparent"
                HoverHandler { id: hover }
                TapHandler { onTapped: App.copy(rowItem.modelData.value, rowItem.modelData.label) }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 16
                    Text {
                        text: rowItem.modelData.label
                        color: Theme.textDim
                        font.pixelSize: Theme.fontSmall + 1
                        Layout.preferredWidth: 190
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: 5
                        elide: Text.ElideRight
                    }
                    Text {
                        id: value
                        text: rowItem.modelData.value
                        color: Theme.text
                        font.pixelSize: Theme.fontSmall + 1
                        Layout.fillWidth: true
                        wrapMode: Text.WrapAnywhere
                        textFormat: Text.PlainText
                        maximumLineCount: 6
                        elide: Text.ElideRight
                    }
                    Icon { name: "copy"; size: 14; opacity: hover.hovered ? 0.6 : 0 }
                }
            }
        }
    }
}
