import QtQuick

// Thin rounded progress bar; indeterminate shows a moving sheen.
Item {
    id: root
    property real value: 0
    property bool indeterminate: false
    property color color: Theme.accentBright
    implicitHeight: 6
    implicitWidth: 200

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.12)
        clip: true
        Rectangle {
            visible: !root.indeterminate
            width: Math.max(root.value > 0 ? parent.height : 0, parent.width * Math.max(0, Math.min(1, root.value)))
            height: parent.height
            radius: height / 2
            color: root.color
            Behavior on width { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
        }
        Rectangle {
            id: sheen
            visible: root.indeterminate
            width: parent.width * 0.3
            height: parent.height
            radius: height / 2
            color: root.color
            NumberAnimation on x {
                running: root.indeterminate && root.visible
                from: -sheen.width
                to: root.width
                duration: 1200
                loops: Animation.Infinite
            }
        }
    }
}
