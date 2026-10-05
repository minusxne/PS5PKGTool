import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import PS5PkgTool.Native

// A sortable, filterable table for {columns, rows} data from the bridge.
ColumnLayout {
    id: root
    property var table: ({ columns: [], rows: [] })
    property string filter: ""
    property bool showSearch: true
    property string emptyText: qsTr("Nothing to show.")
    property alias model: tableModel
    signal rowActivated(var row)
    spacing: 8

    TableModel {
        id: tableModel
        table: root.table || ({ columns: [], rows: [] })
        filter: search.text
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.showSearch
        PsTextField {
            id: search
            icon: "search"
            clearable: true
            placeholderText: qsTr("Filter rows")
            Layout.preferredWidth: 280
            text: root.filter
        }
        Text {
            text: tableModel.count === tableModel.totalCount ? qsTr("%1 rows").arg(tableModel.totalCount)
                                                             : qsTr("%1 of %2 rows").arg(tableModel.count).arg(tableModel.totalCount)
            color: Theme.textFaint
            font.pixelSize: Theme.fontSmall
        }
        Item { Layout.fillWidth: true }
        PsButton { compact: true; iconName: "copy"; text: qsTr("Copy"); onClicked: App.copy(tableModel.copyText(-1), qsTr("Table")) }
    }

    Card {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Theme.radius
        clip: true

        HorizontalHeaderView {
            id: header
            syncView: tableView
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 1
            clip: true
            delegate: Rectangle {
                id: headerCell
                required property int index
                required property string display
                implicitHeight: 36
                implicitWidth: 80
                color: Theme.surfaceRaised
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    spacing: 4
                    Text {
                        text: headerCell.display
                        color: Theme.textDim
                        font.pixelSize: Theme.fontSmall
                        font.weight: Font.DemiBold
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                    }
                    Icon {
                        visible: tableModel.sortColumn === headerCell.index
                        name: tableModel.sortAscending ? "chevron-up" : "chevron-down"
                        size: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                TapHandler { onTapped: tableModel.sortBy(headerCell.index) }
            }
        }

        TableView {
            id: tableView
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: header.bottom
            anchors.bottom: parent.bottom
            anchors.margins: 1
            clip: true
            model: tableModel
            boundsBehavior: Flickable.StopAtBounds
            columnWidthProvider: function (column) { return Math.max(70, tableModel.columnWidth(column, 7)) }
            ScrollBar.vertical: ScrollBar {}
            ScrollBar.horizontal: ScrollBar {}
            delegate: Rectangle {
                id: cell
                required property int row
                required property int column
                required property string display
                implicitHeight: 32
                color: row % 2 === 0 ? "transparent" : Qt.rgba(1, 1, 1, 0.025)
                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 6
                    text: cell.display
                    color: Theme.text
                    font.pixelSize: Theme.fontSmall + 1
                    font.family: /^0x|^[0-9A-F]{8,}$/.test(cell.display) ? "monospace" : Qt.application.font.family
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
                TapHandler {
                    onDoubleTapped: root.rowActivated(tableModel.rowAt(cell.row))
                    onLongPressed: App.copy(cell.display)
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: tableModel.count === 0
            text: tableModel.totalCount === 0 ? root.emptyText : qsTr("No rows match the filter.")
            color: Theme.textFaint
            font.pixelSize: Theme.fontBody
        }
    }
}
