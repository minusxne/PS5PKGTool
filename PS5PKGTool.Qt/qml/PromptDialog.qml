import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

PsDialog {
    id: dialog
    property string label: ""
    property var onAccept: null
    confirmEnabled: field.text.trim().length > 0

    function ask(options) {
        title = options.title
        label = options.label || ""
        field.text = options.value || ""
        confirmLabel = options.confirmLabel || qsTr("Save")
        onAccept = options.onAccept
        open()
        field.forceActiveFocus()
    }
    onAccepted: if (onAccept) onAccept(field.text.trim())

    Text { text: dialog.label; color: Theme.textDim; font.pixelSize: Theme.fontSmall + 1 }
    PsTextField { id: field; Layout.fillWidth: true; onAccepted: if (dialog.confirmEnabled) dialog.accept() }
}
