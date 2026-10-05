import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import PS5PkgTool.Native

// Grouped property cards in two columns, plus localized titles and section health.
Flickable {
    id: root
    property var details: null
    contentHeight: grid.implicitHeight + 20
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {}

    GridLayout {
        id: grid
        width: root.width - 12
        columns: width > 1100 ? 2 : 1
        columnSpacing: 16
        rowSpacing: 16

        Repeater {
            model: root.details ? root.details.overview : []
            delegate: PropertyList {
                required property var modelData
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                title: modelData.title
                rows: modelData.rows
            }
        }

        Card {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            visible: root.details && root.details.localizedTitles.length > 1
            implicitHeight: titlesColumn.implicitHeight + 32
            ColumnLayout {
                id: titlesColumn
                anchors.fill: parent
                anchors.margins: 16
                spacing: 6
                Text { text: qsTr("Localized titles"); color: Theme.text; font.pixelSize: Theme.fontBody + 1; font.weight: Font.DemiBold }
                Repeater {
                    model: root.details ? root.details.localizedTitles : []
                    delegate: RowLayout {
                        required property var modelData
                        spacing: 16
                        Text { text: modelData.language; color: Theme.textDim; font.pixelSize: Theme.fontSmall + 1; Layout.preferredWidth: 80 }
                        Text { text: modelData.title; color: Theme.text; font.pixelSize: Theme.fontSmall + 1; Layout.fillWidth: true; elide: Text.ElideRight }
                    }
                }
            }
        }

        Card {
            Layout.fillWidth: true
            Layout.columnSpan: grid.columns
            visible: root.details && root.details.errors.length > 0
            implicitHeight: errorsColumn.implicitHeight + 32
            border.color: Qt.rgba(1, 0.71, 0.29, 0.4)
            ColumnLayout {
                id: errorsColumn
                anchors.fill: parent
                anchors.margins: 16
                spacing: 6
                RowLayout {
                    Icon { name: "warning"; color: Theme.warning; size: 18 }
                    Text { text: qsTr("Some parts could not be read"); color: Theme.text; font.weight: Font.DemiBold }
                }
                Repeater {
                    model: root.details ? root.details.errors : []
                    delegate: Text { required property string modelData; text: "• " + modelData; color: Theme.textDim; font.pixelSize: Theme.fontSmall + 1; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                }
            }
        }
    }
}
