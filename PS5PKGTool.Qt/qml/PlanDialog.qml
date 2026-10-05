import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// Preview of a rename or move: every item with its new name/place, conflicts and skips, before
// anything is touched.
PsDialog {
    id: dialog
    property var items: []
    property var onAccept: null
    width: Math.min(parent ? parent.width - 80 : 900, 900)
    readonly property int actionable: items.filter(function (item) { return item.status === "rename" || item.status === "conflict" || item.status === "move" }).length
    readonly property int conflicts: items.filter(function (item) { return item.status === "conflict" }).length
    readonly property int skipped: items.filter(function (item) { return item.status === "error" }).length
    readonly property int unchanged: items.filter(function (item) { return item.status === "unchanged" }).length
    confirmEnabled: actionable > 0

    function show(options) {
        title = options.title
        subtitle = options.subtitle || ""
        items = options.items
        confirmLabel = options.confirmLabel || qsTr("Apply")
        onAccept = options.onAccept
        open()
    }
    onAccepted: if (onAccept) onAccept()

    RowLayout {
        spacing: 8
        Badge { text: qsTr("%1 to change").arg(dialog.actionable); tint: Theme.accentBright }
        Badge { visible: dialog.conflicts > 0; text: qsTr("%1 renamed to avoid a clash").arg(dialog.conflicts); tint: Theme.warning }
        Badge { visible: dialog.unchanged > 0; text: qsTr("%1 unchanged").arg(dialog.unchanged); tint: Theme.textDim }
        Badge { visible: dialog.skipped > 0; text: qsTr("%1 skipped").arg(dialog.skipped); tint: Theme.danger }
    }

    ListView {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(420, contentHeight)
        clip: true
        model: dialog.items
        spacing: 2
        ScrollBar.vertical: ScrollBar {}
        delegate: Rectangle {
            id: entry
            required property var modelData
            width: ListView.view.width
            height: 54
            radius: 8
            color: Qt.rgba(1, 1, 1, 0.04)
            readonly property color tint: modelData.status === "error" ? Theme.danger : modelData.status === "conflict" ? Theme.warning
                                         : modelData.status === "unchanged" ? Theme.textFaint : Theme.success
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 12
                Icon {
                    name: entry.modelData.status === "error" ? "error" : entry.modelData.status === "unchanged" ? "check" : entry.modelData.status === "conflict" ? "warning" : "chevron-right"
                    size: 18
                    color: entry.tint
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { text: entry.modelData.name; color: Theme.textDim; font.pixelSize: Theme.fontSmall + 1; Layout.fillWidth: true; elide: Text.ElideMiddle }
                    Text {
                        text: entry.modelData.status === "error" || entry.modelData.status === "unchanged"
                              ? entry.modelData.note : "→ " + entry.modelData.targetName + (entry.modelData.note ? "   (" + entry.modelData.note + ")" : "")
                        color: entry.modelData.status === "error" ? Theme.danger : Theme.text
                        font.pixelSize: Theme.fontBody
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                    }
                }
            }
        }
    }
}
