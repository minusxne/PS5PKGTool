import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import PS5PkgTool.Native

// The PS5 home layout: one row of game tiles with the focused title's hero underneath.
FocusScope {
    id: home
    focus: true
    readonly property int tileSize: Math.max(108, Math.min(150, height * 0.19))

    ListView {
        id: rail
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: -6
        height: home.tileSize + 34
        orientation: ListView.Horizontal
        spacing: 14
        clip: false
        focus: true
        model: Library.games
        cacheBuffer: 1200
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: Theme.normal
        highlightRangeMode: ListView.ApplyRange
        preferredHighlightBegin: 6
        preferredHighlightEnd: width * 0.62
        keyNavigationEnabled: false
        // The selection (App.selectedId) is the source of truth; the view follows it.
        function sync() {
            const index = Library.games.indexOf(App.selectedId)
            if (index >= 0 && index !== currentIndex) currentIndex = index
        }
        function step(delta) {
            const index = Math.max(0, Math.min(count - 1, currentIndex + delta))
            const id = Library.games.idAt(index)
            if (id.length > 0) App.selectedId = id
        }
        Component.onCompleted: sync()
        Connections {
            target: App
            function onSelectedIdChanged() { rail.sync() }
        }
        Connections {
            target: Library
            function onViewChanged() { Qt.callLater(rail.sync) }
        }
        Keys.onLeftPressed: step(-1)
        Keys.onRightPressed: step(1)
        Keys.onReturnPressed: App.openDetails(App.selectedId)
        Keys.onEnterPressed: App.openDetails(App.selectedId)
        Keys.onMenuPressed: App.menuRequested([App.selectedId], null)
        Keys.onDownPressed: hero.forceActiveFocus()

        delegate: GameTile {
            required property int index
            required property var model
            y: 12
            tileSize: home.tileSize
            gameId: model.gameId
            title: model.title
            iconUrl: model.iconUrl
            format: model.format
            role: model.role
            missing: model.missing
            current: ListView.isCurrentItem
            onClicked: { App.selectedId = gameId; rail.forceActiveFocus() }
            onActivated: App.openDetails(gameId)
            onContextRequested: { App.selectedId = gameId; App.menuRequested([gameId], null) }
        }

        WheelHandler {
            orientation: Qt.Vertical
            onWheel: (event) => {
                rail.step(event.angleDelta.y > 0 ? -1 : 1)
            }
        }
    }

    HeroPanel {
        id: hero
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: rail.bottom
        anchors.bottom: parent.bottom
        anchors.topMargin: 18
        row: App.selectedRow
        KeyNavigation.up: rail
    }
}
