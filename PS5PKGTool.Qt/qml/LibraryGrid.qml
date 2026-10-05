import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import PS5PkgTool.Native

// The game library grid: every item as a tile with its title.
FocusScope {
    id: root
    focus: true
    readonly property int tile: 150

    GridView {
        id: grid
        anchors.fill: parent
        anchors.topMargin: 6
        clip: true
        focus: true
        model: Library.games
        cellWidth: Math.floor(width / Math.max(1, Math.floor(width / (root.tile + 34))))
        cellHeight: root.tile + 76
        cacheBuffer: 800
        keyNavigationEnabled: false
        function sync() {
            const index = Library.games.indexOf(App.selectedId)
            if (index >= 0 && index !== currentIndex) { currentIndex = index; positionViewAtIndex(index, GridView.Contain) }
        }
        function selectIndex(index) {
            const id = Library.games.idAt(Math.max(0, Math.min(count - 1, index)))
            if (id.length > 0) App.selectedId = id
        }
        readonly property int columns: Math.max(1, Math.floor(width / cellWidth))
        Component.onCompleted: sync()
        Connections {
            target: App
            function onSelectedIdChanged() { grid.sync() }
        }
        Connections {
            target: Library
            function onViewChanged() { Qt.callLater(grid.sync) }
        }
        Keys.onLeftPressed: selectIndex(currentIndex - 1)
        Keys.onRightPressed: selectIndex(currentIndex + 1)
        Keys.onUpPressed: selectIndex(currentIndex - columns)
        Keys.onDownPressed: selectIndex(currentIndex + columns)
        Keys.onReturnPressed: App.openDetails(App.selectedId)
        Keys.onEnterPressed: App.openDetails(App.selectedId)
        Keys.onMenuPressed: App.menuRequested([App.selectedId], null)
        ScrollBar.vertical: ScrollBar {}

        delegate: Item {
            id: cell
            required property int index
            required property string gameId
            required property string title
            required property string iconUrl
            required property string format
            required property string role
            required property bool missing
            width: grid.cellWidth
            height: grid.cellHeight
            GameTile {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 12
                tileSize: root.tile
                showTitle: true
                gameId: cell.gameId
                title: cell.title
                iconUrl: cell.iconUrl
                format: cell.format
                role: cell.role
                missing: cell.missing
                current: grid.currentIndex === cell.index
                onClicked: { App.selectedId = cell.gameId; grid.forceActiveFocus() }
                onActivated: App.openDetails(cell.gameId)
                onContextRequested: { App.selectedId = cell.gameId; App.menuRequested([cell.gameId], null) }
            }
        }
    }
}
