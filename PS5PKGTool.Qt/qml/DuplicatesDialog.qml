import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import PS5PkgTool.Native

// Duplicate copies grouped by content ID; "identical" means the param.json hashes match.
PsDialog {
    id: dialog
    property var groups: []
    property int identical: 0
    width: Math.min(parent ? parent.width - 80 : 960, 960)
    title: qsTr("Duplicates")
    confirmLabel: qsTr("Close")
    showCancel: false

    function show(result) {
        groups = result.groups
        identical = result.identical
        subtitle = groups.length === 0 ? qsTr("No duplicates found.")
                 : qsTr("%1 group(s): %2 byte-identical, %3 possible (same IDs, different contents)")
                       .arg(groups.length).arg(identical).arg(groups.length - identical)
        open()
    }

    ListView {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(480, contentHeight)
        visible: dialog.groups.length > 0
        clip: true
        spacing: 10
        model: dialog.groups
        ScrollBar.vertical: ScrollBar {}
        delegate: Card {
            id: group
            required property var modelData
            width: ListView.view.width
            height: groupColumn.implicitHeight + 24
            raised: true
            ColumnLayout {
                id: groupColumn
                anchors.fill: parent
                anchors.margins: 12
                spacing: 6
                RowLayout {
                    Text { text: group.modelData.title || group.modelData.key; color: Theme.text; font.weight: Font.DemiBold; font.pixelSize: Theme.fontBody; Layout.fillWidth: true; elide: Text.ElideRight }
                    Badge { text: group.modelData.verdict === "identical" ? qsTr("Identical") : qsTr("Possible"); tint: group.modelData.verdict === "identical" ? Theme.success : Theme.warning }
                }
                Repeater {
                    model: group.modelData.items
                    delegate: RowLayout {
                        id: copy
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 10
                        Badge { text: copy.modelData.format; tint: Theme.accentBright }
                        Text { text: copy.modelData.sizeText; color: Theme.textDim; font.pixelSize: Theme.fontSmall + 1; Layout.preferredWidth: 80 }
                        Text { text: copy.modelData.id; color: Theme.text; font.pixelSize: Theme.fontSmall + 1; Layout.fillWidth: true; elide: Text.ElideMiddle }
                        IconButton { iconName: "folder"; size: 28; tip: qsTr("Show"); onClicked: App.revealItem(copy.modelData.id) }
                        IconButton { iconName: "trash"; size: 28; tip: qsTr("Remove this copy"); onClicked: { dialog.close(); App.remove([copy.modelData.id]) } }
                    }
                }
            }
        }
    }
}
