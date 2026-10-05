import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// Centered modal card with a title, content and right-aligned actions.
Popup {
    id: dialog
    property string title: ""
    property string subtitle: ""
    property string confirmLabel: qsTr("OK")
    property string cancelLabel: qsTr("Cancel")
    property bool danger: false
    property bool showCancel: true
    property bool confirmEnabled: true
    default property alias body: bodyColumn.data
    signal accepted()
    signal rejected()

    parent: Overlay.overlay
    anchors.centerIn: parent
    modal: true
    focus: true
    width: Math.min(parent ? parent.width - 80 : 640, 640)
    padding: 26
    closePolicy: Popup.CloseOnEscape
    onClosed: if (!acceptedOnce) rejected()
    property bool acceptedOnce: false
    onAboutToShow: acceptedOnce = false

    function accept() {
        acceptedOnce = true
        close()
        accepted()
    }

    Overlay.modal: Rectangle { color: Theme.scrim; Behavior on opacity { NumberAnimation { duration: Theme.fast } } }
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.normal }
        NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Theme.normal; easing.type: Easing.OutCubic }
    }
    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Theme.fast } }

    background: Rectangle { radius: Theme.radiusLarge + 4; color: Theme.surfaceSolid; border.color: Theme.outline }

    contentItem: ColumnLayout {
        spacing: 16
        ColumnLayout {
            spacing: 4
            Text { text: dialog.title; color: Theme.text; font.pixelSize: Theme.fontTitle - 6; font.weight: Font.DemiBold; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            Text { visible: dialog.subtitle.length > 0; text: dialog.subtitle; color: Theme.textDim; font.pixelSize: Theme.fontSmall + 1; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere }
        }
        ColumnLayout {
            id: bodyColumn
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 10
            Item { Layout.fillWidth: true }
            PsButton { visible: dialog.showCancel; text: dialog.cancelLabel; onClicked: dialog.close() }
            PsButton {
                text: dialog.confirmLabel
                variant: dialog.danger ? "danger" : "primary"
                enabled: dialog.confirmEnabled
                focus: true
                onClicked: dialog.accept()
            }
        }
    }
}
