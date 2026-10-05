import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

PsDialog {
    id: dialog
    property string text: ""
    property var items: []
    property var onAccept: null
    property var onReject: null

    function ask(options) {
        title = options.title || ""
        subtitle = options.subtitle || ""
        text = options.text || ""
        items = options.items || []
        confirmLabel = options.confirmLabel || qsTr("OK")
        cancelLabel = options.cancelLabel || qsTr("Cancel")
        danger = !!options.danger
        onAccept = options.onAccept || null
        onReject = options.onReject || null
        open()
    }
    onAccepted: if (onAccept) onAccept()
    onRejected: if (onReject) onReject()

    Text { text: dialog.text; visible: text.length > 0; color: Theme.textDim; font.pixelSize: Theme.fontBody; wrapMode: Text.WordWrap; Layout.fillWidth: true }
    Rectangle {
        visible: dialog.items.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(220, itemsColumn.implicitHeight + 20)
        radius: Theme.radius
        color: Qt.rgba(1, 1, 1, 0.05)
        Flickable {
            anchors.fill: parent
            anchors.margins: 10
            contentHeight: itemsColumn.implicitHeight
            clip: true
            Column {
                id: itemsColumn
                width: parent.width
                spacing: 4
                Repeater {
                    model: dialog.items
                    delegate: Text { required property string modelData; text: modelData; color: Theme.text; font.pixelSize: Theme.fontSmall + 1; width: itemsColumn.width; elide: Text.ElideMiddle }
                }
            }
        }
    }
}
