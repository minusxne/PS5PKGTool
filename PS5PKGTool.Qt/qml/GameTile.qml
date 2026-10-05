import QtQuick
import QtQuick.Effects
import PS5PkgTool.Native

// A square game tile with its icon0 art. The focused tile grows and gets a white ring, as on the
// PS5 home screen; missing art falls back to a format glyph.
Item {
    id: root
    property string gameId: ""
    property string title: ""
    property string iconUrl: ""
    property string format: ""
    property string role: ""
    property bool missing: false
    property bool current: false
    property bool showTitle: false
    property int tileSize: 120
    signal activated()
    signal clicked()
    signal contextRequested(real x, real y)

    implicitWidth: tileSize
    implicitHeight: tileSize + (showTitle ? 44 : 0)

    Component.onCompleted: if (iconUrl.length === 0 && gameId.length > 0) Library.requestArt(gameId, false)
    onGameIdChanged: if (iconUrl.length === 0 && gameId.length > 0) Library.requestArt(gameId, false)

    Item {
        id: tile
        width: root.tileSize
        height: root.tileSize
        scale: root.current ? 1.0 : (hover.hovered ? 0.96 : 0.92)
        transformOrigin: Item.Bottom
        Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }

        Rectangle {
            id: art
            anchors.fill: parent
            radius: Theme.radius + 2
            color: Theme.surfaceRaised
            clip: true
            layer.enabled: Theme.effects
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: mask
                shadowEnabled: root.current
                shadowBlur: 0.8
                shadowColor: "#c0000000"
                shadowVerticalOffset: 8
            }

            Rectangle {
                anchors.fill: parent
                visible: image.status !== Image.Ready
                gradient: Gradient {
                    GradientStop { position: 0; color: "#24324a" }
                    GradientStop { position: 1; color: "#121826" }
                }
                Icon { anchors.centerIn: parent; name: Theme.formatIcon(root.format); size: root.tileSize * 0.32; opacity: 0.5 }
                Text {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 10
                    text: root.title
                    color: Theme.textDim
                    font.pixelSize: Math.max(10, root.tileSize * 0.09)
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                }
            }
            Image {
                id: image
                anchors.fill: parent
                source: root.iconUrl
                sourceSize: Qt.size(256, 256)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                opacity: status === Image.Ready ? (root.missing ? 0.35 : 1) : 0
                Behavior on opacity { NumberAnimation { duration: Theme.normal } }
            }
        }
        Item {
            id: mask
            anchors.fill: parent
            layer.enabled: true
            visible: false
            Rectangle { anchors.fill: parent; radius: Theme.radius + 2; color: "black" }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: -5
            radius: Theme.radius + 7
            color: "transparent"
            border.width: 3
            border.color: "white"
            opacity: root.current ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.normal } }
        }

        Badge {
            visible: root.role === "Update" || root.role === "Update (older)" || root.role === "DLC"
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 8
            text: root.role === "DLC" ? "DLC" : "UPD"
            tint: Theme.roleColor(root.role)
            solid: true
            implicitHeight: 20
        }
        Badge {
            visible: root.missing
            anchors.centerIn: parent
            text: qsTr("MISSING")
            tint: Theme.danger
            solid: true
        }

        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: root.clicked()
            onDoubleTapped: root.activated()
        }
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: (point) => root.contextRequested(point.position.x, point.position.y)
        }
    }

    Text {
        visible: root.showTitle
        anchors.top: tile.bottom
        anchors.topMargin: 10
        width: root.tileSize
        text: root.title
        color: root.current ? Theme.text : Theme.textDim
        font.pixelSize: Theme.fontSmall + 1
        font.weight: root.current ? Font.DemiBold : Font.Normal
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
    }
}
