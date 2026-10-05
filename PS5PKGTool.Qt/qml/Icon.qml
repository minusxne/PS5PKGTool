import QtQuick
import QtQuick.Effects

// A stroke icon from resources/icons, optionally tinted.
Item {
    id: root
    property string name: ""
    property int size: 22
    property color color: "white"
    readonly property bool tinted: !Qt.colorEqual(color, "white") && Theme.effects

    implicitWidth: size
    implicitHeight: size

    Image {
        id: image
        anchors.fill: parent
        source: root.name.length > 0 ? Qt.resolvedUrl("icons/" + root.name + ".svg") : ""
        sourceSize: Qt.size(root.size * 2, root.size * 2)
        smooth: true
        visible: !root.tinted
    }

    MultiEffect {
        anchors.fill: image
        source: image
        visible: root.tinted
        colorization: 1.0
        colorizationColor: root.color
        brightness: 1.0
    }
}
