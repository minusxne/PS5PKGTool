import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// The raw sce_sys/param.json, formatted or byte-for-byte.
ColumnLayout {
    id: root
    property var details: null
    property bool formatted: true
    spacing: 12

    RowLayout {
        Chip { text: qsTr("Formatted"); selected: root.formatted; onClicked: root.formatted = true }
        Chip { text: qsTr("Original"); selected: !root.formatted; onClicked: root.formatted = false }
        Item { Layout.fillWidth: true }
        PsButton { compact: true; iconName: "copy"; text: qsTr("Copy JSON"); onClicked: App.copy(viewer.text, "param.json") }
    }
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Theme.radius
        color: Qt.rgba(0, 0, 0, 0.4)
        border.color: Theme.outline
        ScrollView {
            anchors.fill: parent
            anchors.margins: 14
            TextArea {
                id: viewer
                readOnly: true
                selectByMouse: true
                text: root.details ? (root.formatted ? root.details.rawParam.formatted : root.details.rawParam.original) : ""
                color: Theme.text
                font.family: "monospace"
                font.pixelSize: Theme.fontSmall + 1
                wrapMode: TextEdit.NoWrap
                background: null
            }
        }
        Text { anchors.centerIn: parent; visible: viewer.text.length === 0; text: qsTr("No param.json was read for this source."); color: Theme.textFaint }
    }
}
