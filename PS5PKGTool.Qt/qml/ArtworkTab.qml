import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import PS5PkgTool.Native

// Every artwork slot with its format and size; click to view full screen, save one or all.
Item {
    id: root
    property var details: null
    property string viewing: ""

    ColumnLayout {
        anchors.fill: parent
        spacing: 14
        RowLayout {
            Text { text: qsTr("Artwork"); color: Theme.text; font.pixelSize: Theme.fontHeading; font.weight: Font.DemiBold; Layout.fillWidth: true }
            PsButton { compact: true; iconName: "image"; text: qsTr("Save all…"); onClicked: App.saveArtwork([root.details.row.id]) }
        }
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: flow.implicitHeight
            clip: true
            ScrollBar.vertical: ScrollBar {}
            Flow {
                id: flow
                width: parent.width
                spacing: 18
                Repeater {
                    model: root.details ? root.details.artwork : []
                    delegate: Card {
                        id: slot
                        required property var modelData
                        readonly property bool square: modelData.key === "icon0"
                        width: square ? 300 : 520
                        height: (square ? 300 : 292) + 70
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: Theme.radius
                                color: Qt.rgba(0, 0, 0, 0.3)
                                clip: true
                                Image {
                                    anchors.fill: parent
                                    source: slot.modelData.path ? Desktop.fileUrl(slot.modelData.path) : ""
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    sourceSize: Qt.size(1024, 1024)
                                }
                                Text { anchors.centerIn: parent; visible: !slot.modelData.present; text: qsTr("Not present"); color: Theme.textFaint }
                                TapHandler { enabled: slot.modelData.present; onTapped: root.viewing = Desktop.fileUrl(slot.modelData.path) }
                                HoverHandler { cursorShape: slot.modelData.present ? Qt.PointingHandCursor : Qt.ArrowCursor }
                            }
                            RowLayout {
                                Text { text: slot.modelData.label; color: Theme.text; font.weight: Font.DemiBold }
                                Text {
                                    text: slot.modelData.present ? slot.modelData.format + (slot.modelData.width > 0 ? " · " + slot.modelData.width + "×" + slot.modelData.height : "") : "—"
                                    color: Theme.textFaint; font.pixelSize: Theme.fontSmall + 1; Layout.fillWidth: true
                                }
                                IconButton {
                                    visible: slot.modelData.present
                                    iconName: "export"; size: 30; tip: qsTr("Save as…")
                                    onClicked: App.saveFile(qsTr("Save image"), (root.details.row.titleId || "artwork") + "-" + slot.modelData.key + ".png", ["PNG images (*.png)"],
                                                            function (path) { if (Desktop.copyFile(slot.modelData.path, path)) App.toast(qsTr("Saved"), path, "success", "image") })
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Full-screen viewer
    Rectangle {
        anchors.fill: parent
        visible: root.viewing.length > 0
        color: Qt.rgba(0, 0, 0, 0.92)
        radius: Theme.radius
        Image { anchors.fill: parent; anchors.margins: 20; source: root.viewing; fillMode: Image.PreserveAspectFit; asynchronous: true }
        IconButton { anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 12; iconName: "close"; onClicked: root.viewing = "" }
        TapHandler { onTapped: root.viewing = "" }
    }
}
