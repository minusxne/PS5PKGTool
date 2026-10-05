import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// Activities & UDS: events with their properties, statistics, enum groups and extraction rules.
Item {
    id: root
    property var details: null
    readonly property var uds: details ? details.activities : null
    property string section: "events"
    property int eventIndex: 0

    EmptyState {
        anchors.centerIn: parent
        visible: !root.uds || !root.uds.present
        icon: "activity"
        title: qsTr("No activities")
        text: root.uds ? root.uds.message : ""
    }

    ColumnLayout {
        anchors.fill: parent
        visible: !!root.uds && root.uds.present
        spacing: 12

        RowLayout {
            TabStrip {
                current: root.section
                fontSize: Theme.fontBody
                tabs: [
                    { key: "events", label: qsTr("Events (%1)").arg(root.uds && root.uds.present ? root.uds.events.length : 0) },
                    { key: "stats", label: qsTr("Stats (%1)").arg(root.uds && root.uds.present ? root.uds.stats.rows.length : 0) },
                    { key: "enums", label: qsTr("Enum groups (%1)").arg(root.uds && root.uds.present ? root.uds.enums.rows.length : 0) },
                    { key: "rules", label: qsTr("Rules (%1)").arg(root.uds && root.uds.present ? root.uds.rules.rows.length : 0) }
                ]
                onSelected: (key) => root.section = key
            }
            Item { Layout.fillWidth: true }
            Text {
                text: root.uds && root.uds.present ? root.uds.npCommunicationId + " · " + (root.uds.integrityValid ? qsTr("integrity OK") : qsTr("integrity check failed")) : ""
                color: Theme.textFaint; font.pixelSize: Theme.fontSmall + 1
            }
        }

        RowLayout {
            visible: root.section === "events"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16
            Card {
                Layout.preferredWidth: 380
                Layout.fillHeight: true
                ListView {
                    id: events
                    anchors.fill: parent
                    anchors.margins: 8
                    clip: true
                    model: root.uds && root.uds.present ? root.uds.events : []
                    currentIndex: root.eventIndex
                    ScrollBar.vertical: ScrollBar {}
                    delegate: Rectangle {
                        id: eventRow
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        height: 52
                        radius: 8
                        color: index === root.eventIndex ? Theme.accentSoft : hover.hovered ? Theme.surfaceHover : "transparent"
                        HoverHandler { id: hover }
                        TapHandler { onTapped: root.eventIndex = eventRow.index }
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 1
                            Text { text: eventRow.modelData.name; color: Theme.text; font.pixelSize: Theme.fontBody; elide: Text.ElideRight; Layout.fillWidth: true; Layout.topMargin: 8 }
                            Text { text: [eventRow.modelData.type, eventRow.modelData.group, qsTr("%1 properties").arg(eventRow.modelData.properties.length)].filter(Boolean).join(" · "); color: Theme.textFaint; font.pixelSize: Theme.fontSmall; elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                    }
                }
            }
            DataTable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                emptyText: qsTr("This event has no properties.")
                table: {
                    const list = root.uds && root.uds.present ? root.uds.events : []
                    const event = list[root.eventIndex]
                    return {
                        columns: [qsTr("Property"), qsTr("Type"), qsTr("Item type"), qsTr("Mapped")],
                        rows: event ? event.properties.map(function (p) { return [p.path, p.type, p.itemType, p.mapped] }) : []
                    }
                }
            }
        }
        DataTable { visible: root.section === "stats"; Layout.fillWidth: true; Layout.fillHeight: true; table: root.uds && root.uds.present ? root.uds.stats : ({}) }
        DataTable { visible: root.section === "enums"; Layout.fillWidth: true; Layout.fillHeight: true; table: root.uds && root.uds.present ? root.uds.enums : ({}) }
        DataTable { visible: root.section === "rules"; Layout.fillWidth: true; Layout.fillHeight: true; table: root.uds && root.uds.present ? root.uds.rules : ({}) }
    }
}
