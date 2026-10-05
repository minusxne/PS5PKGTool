import QtQuick
import QtQuick.Layouts

// PS5-style notification cards stacked in the top-right corner.
Item {
    id: host
    width: 380
    height: column.implicitHeight

    ListModel { id: toasts }
    property int serial: 0
    property var actions: ({})

    function show(toast) {
        const id = ++serial
        actions[id] = toast.action
        toasts.insert(0, { uid: id, title: toast.title, body: toast.body, kind: toast.kind, icon: toast.icon,
                           actionLabel: toast.action ? toast.action.label : "" })
        while (toasts.count > 4) toasts.remove(toasts.count - 1)
    }

    function dismiss(uid) {
        for (let i = 0; i < toasts.count; ++i)
            if (toasts.get(i).uid === uid) { toasts.remove(i); break }
        delete actions[uid]
    }

    Column {
        id: column
        width: parent.width
        spacing: 10
        move: Transition { NumberAnimation { properties: "y"; duration: Theme.normal; easing.type: Easing.OutCubic } }
        add: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.normal }
            NumberAnimation { property: "x"; from: 40; to: 0; duration: Theme.normal; easing.type: Easing.OutCubic }
        }

        Repeater {
            model: toasts
            delegate: Rectangle {
                id: card
                required property int uid
                required property string title
                required property string body
                required property string kind
                required property string icon
                required property string actionLabel
                readonly property color tint: kind === "success" ? Theme.success : kind === "error" ? Theme.danger
                                             : kind === "warning" ? Theme.warning : Theme.accentBright
                width: column.width
                height: content.implicitHeight + 28
                radius: Theme.radius + 2
                color: Theme.surfaceRaised
                border.color: Theme.outline

                Timer {
                    interval: card.kind === "error" ? 9000 : 5200
                    running: !hover.hovered
                    onTriggered: host.dismiss(card.uid)
                }
                HoverHandler { id: hover }

                Rectangle { width: 4; radius: 2; color: card.tint; anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.margins: 12 }

                RowLayout {
                    id: content
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    anchors.leftMargin: 26
                    spacing: 12
                    Icon { name: card.icon.length > 0 ? card.icon : "info"; size: 22; color: card.tint; Layout.alignment: Qt.AlignTop }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        Text { text: card.title; color: Theme.text; font.pixelSize: Theme.fontBody; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                        Text {
                            text: card.body
                            visible: text.length > 0
                            color: Theme.textDim
                            font.pixelSize: Theme.fontSmall + 1
                            wrapMode: Text.WrapAnywhere
                            maximumLineCount: 4
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        PsButton {
                            visible: card.actionLabel.length > 0
                            compact: true
                            text: card.actionLabel
                            Layout.topMargin: 4
                            onClicked: {
                                const action = host.actions[card.uid]
                                if (action && action.run) action.run()
                                host.dismiss(card.uid)
                            }
                        }
                    }
                    IconButton { iconName: "close"; size: 28; Layout.alignment: Qt.AlignTop; onClicked: host.dismiss(card.uid) }
                }
            }
        }
    }
}
