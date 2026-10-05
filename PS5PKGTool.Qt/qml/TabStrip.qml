import QtQuick
import QtQuick.Controls.Basic

// Text tabs with an underline, PS5 style.
Row {
    id: root
    property var tabs: []           // [{key, label}] or strings
    property string current: ""
    property int fontSize: Theme.fontBody + 1
    signal selected(string key)
    spacing: 26

    Repeater {
        model: root.tabs
        delegate: AbstractButton {
            id: tab
            required property var modelData
            readonly property string key: typeof modelData === "string" ? modelData : modelData.key
            readonly property string label: typeof modelData === "string" ? modelData : modelData.label
            readonly property bool active: root.current === key
            hoverEnabled: true
            focusPolicy: Qt.StrongFocus
            implicitHeight: 40
            implicitWidth: caption.implicitWidth
            onClicked: root.selected(key)
            contentItem: Text {
                id: caption
                text: tab.label
                color: tab.active ? Theme.text : tab.hovered ? Theme.textDim : Theme.textFaint
                font.pixelSize: root.fontSize
                font.weight: tab.active ? Font.DemiBold : Font.Normal
                verticalAlignment: Text.AlignVCenter
                Behavior on color { ColorAnimation { duration: Theme.fast } }
            }
            background: Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 3
                radius: 1.5
                color: tab.visualFocus ? Theme.accentBright : "white"
                opacity: tab.active || tab.visualFocus ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.fast } }
            }
        }
    }
}
