import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import PS5PkgTool.Native

// Read-only text with Copy and Save.
PsDialog {
    id: dialog
    property string text: ""
    width: Math.min(parent ? parent.width - 80 : 900, 900)
    confirmLabel: qsTr("Close")
    showCancel: false

    function show(heading, body) {
        title = heading
        text = body
        open()
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(460, reportText.implicitHeight + 24)
        radius: Theme.radius
        color: Qt.rgba(0, 0, 0, 0.35)
        ScrollView {
            anchors.fill: parent
            anchors.margins: 12
            TextArea {
                id: reportText
                text: dialog.text
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.NoWrap
                color: Theme.text
                font.family: "monospace"
                font.pixelSize: Theme.fontSmall + 1
                background: null
            }
        }
    }
    RowLayout {
        PsButton { compact: true; iconName: "copy"; text: qsTr("Copy"); onClicked: App.copy(dialog.text, dialog.title) }
        PsButton {
            compact: true
            iconName: "export"
            text: qsTr("Save…")
            onClicked: App.saveFile(qsTr("Save report"), "PS5PKGTool-report.txt", ["Text files (*.txt)"], function (path) {
                if (Desktop.writeText(path, dialog.text)) App.toast(qsTr("Saved"), path, "success", "check")
            })
        }
    }
}
