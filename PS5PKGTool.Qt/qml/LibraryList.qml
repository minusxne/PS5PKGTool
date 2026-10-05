import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import PS5PkgTool.Native

// The dense list for large libraries: sortable columns, collapsible groups, multi-select.
FocusScope {
    id: root
    focus: true

    property var selection: ({})
    property int anchorIndex: -1
    readonly property var columns: [
        { key: "Title", label: qsTr("Title"), role: "title", width: 0 },
        { key: "TitleId", label: qsTr("Title ID"), role: "titleId", width: 110 },
        { key: "Role", label: qsTr("Role"), role: "role", width: 120 },
        { key: "Source", label: qsTr("Format"), role: "format", width: 100 },
        { key: "Region", label: qsTr("Region"), role: "region", width: 100 },
        { key: "Version", label: qsTr("Version"), role: "version", width: 100 },
        { key: "Firmware", label: qsTr("Firmware"), role: "firmware", width: 90 },
        { key: "Size", label: qsTr("Size"), role: "sizeText", width: 96 }
    ]
    readonly property int rowHeight: Math.max(36, App.settings.gridRowHeight ? App.settings.gridRowHeight + 16 : 44)

    function selectedIds() {
        const ids = Object.keys(selection).filter(function (id) { return selection[id] })
        return ids.length > 0 ? ids : (App.selectedId ? [App.selectedId] : [])
    }
    function select(index, modifiers) {
        const id = Library.list.idAt(index)
        if (!id) return
        const next = (modifiers & Qt.ControlModifier) ? Object.assign({}, selection) : {}
        if ((modifiers & Qt.ShiftModifier) && anchorIndex >= 0) {
            const from = Math.min(anchorIndex, index), to = Math.max(anchorIndex, index)
            for (let i = from; i <= to; ++i) { const other = Library.list.idAt(i); if (other) next[other] = true }
        } else {
            next[id] = !(modifiers & Qt.ControlModifier) || !selection[id]
            anchorIndex = index
        }
        selection = next
        App.selectedId = id
        list.currentIndex = index
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Header
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 38
            radius: Theme.radiusSmall
            color: Qt.rgba(1, 1, 1, 0.06)
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 64
                anchors.rightMargin: 12
                spacing: 0
                Repeater {
                    model: root.columns
                    delegate: Item {
                        id: headerCell
                        required property var modelData
                        Layout.fillWidth: modelData.width === 0
                        Layout.preferredWidth: modelData.width === 0 ? 200 : modelData.width
                        implicitHeight: 38
                        readonly property string state: {
                            for (let i = 0; i < App.sortKeys.length; ++i)
                                if (App.sortKeys[i].split(":")[0] === modelData.key) return App.sortKeys[i].split(":")[1]
                            return ""
                        }
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            Text { text: headerCell.modelData.label; color: headerCell.state ? Theme.text : Theme.textDim; font.pixelSize: Theme.fontSmall; font.weight: Font.DemiBold }
                            Icon { visible: headerCell.state.length > 0; name: headerCell.state === "asc" ? "chevron-up" : "chevron-down"; size: 12; anchors.verticalCenter: parent.verticalCenter }
                        }
                        TapHandler {
                            acceptedModifiers: Qt.KeyboardModifierMask
                            onTapped: (point) => App.setSort(headerCell.modelData.key, point.modifiers & Qt.ShiftModifier)
                        }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                    }
                }
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 4
            clip: true
            focus: true
            model: Library.list
            cacheBuffer: 1000
            boundsBehavior: Flickable.StopAtBounds
            function sync() {
                const index = Library.list.indexOf(App.selectedId)
                if (index >= 0 && index !== currentIndex) currentIndex = index
            }
            Component.onCompleted: sync()
            Connections {
                target: App
                function onSelectedIdChanged() { list.sync() }
            }
            Connections {
                target: Library
                function onViewChanged() { Qt.callLater(list.sync) }
            }
            ScrollBar.vertical: ScrollBar {}
            Keys.onUpPressed: (event) => { let i = currentIndex - 1; while (i >= 0 && !Library.list.idAt(i)) i--; if (i >= 0) root.select(i, event.modifiers) }
            Keys.onDownPressed: (event) => { let i = currentIndex + 1; while (i < count && !Library.list.idAt(i)) i++; if (i < count) root.select(i, event.modifiers) }
            Keys.onReturnPressed: App.openDetails(App.selectedId)
            Keys.onMenuPressed: App.menuRequested(root.selectedIds(), null)
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
                    const all = {}
                    Library.visibleIds().forEach(function (id) { all[id] = true })
                    root.selection = all
                    event.accepted = true
                }
            }

            delegate: Loader {
                id: rowLoader
                required property int index
                required property string kind
                required property var model
                width: ListView.view.width
                sourceComponent: kind === "header" ? headerRow : gameRow

                Component {
                    id: headerRow
                    Rectangle {
                        height: 40
                        color: "transparent"
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            spacing: 10
                            Icon { name: rowLoader.model.collapsed ? "chevron-right" : "chevron-down"; size: 16 }
                            Text { text: rowLoader.model.groupLabel; color: Theme.text; font.pixelSize: Theme.fontBody; font.weight: Font.DemiBold }
                            Badge { text: rowLoader.model.groupCount; tint: Theme.textDim }
                            Item { Layout.fillWidth: true }
                            IconButton { iconName: "more"; size: 30; tip: qsTr("Group actions"); onClicked: App.menuRequested(Library.list.groupIds(rowLoader.model.groupKey), null) }
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.outline }
                        TapHandler { onTapped: Library.list.toggleGroup(rowLoader.model.groupKey) }
                    }
                }

                Component {
                    id: gameRow
                    Rectangle {
                        id: gameItem
                        readonly property bool selected: !!root.selection[rowLoader.model.gameId] || App.selectedId === rowLoader.model.gameId
                        height: root.rowHeight
                        radius: Theme.radiusSmall
                        color: selected ? Theme.accentSoft : hover.hovered ? Theme.surfaceHover : "transparent"
                        border.width: App.selectedId === rowLoader.model.gameId && list.activeFocus ? 1 : 0
                        border.color: Theme.accentBright
                        HoverHandler { id: hover }
                        TapHandler {
                            acceptedButtons: Qt.LeftButton
                            acceptedModifiers: Qt.KeyboardModifierMask
                            onTapped: (point) => { list.forceActiveFocus(); root.select(rowLoader.index, point.modifiers) }
                            onDoubleTapped: App.openDetails(rowLoader.model.gameId)
                        }
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: {
                                if (!root.selection[rowLoader.model.gameId]) root.select(rowLoader.index, 0)
                                App.menuRequested(root.selectedIds(), null)
                            }
                        }
                        Component.onCompleted: if (!rowLoader.model.iconUrl) Library.requestArt(rowLoader.model.gameId, false)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 12
                            spacing: 0
                            Rectangle {
                                Layout.preferredWidth: root.rowHeight - 10
                                Layout.preferredHeight: root.rowHeight - 10
                                Layout.rightMargin: 64 - root.rowHeight
                                radius: 6
                                color: Theme.surfaceRaised
                                clip: true
                                visible: App.settings.showThumbnails !== false
                                Image {
                                    anchors.fill: parent
                                    source: rowLoader.model.iconUrl || ""
                                    sourceSize: Qt.size(96, 96)
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectCrop
                                    opacity: rowLoader.model.missing ? 0.35 : 1
                                }
                            }
                            Item { visible: App.settings.showThumbnails === false; Layout.preferredWidth: 54 }
                            Repeater {
                                model: root.columns
                                delegate: Text {
                                    required property var modelData
                                    Layout.fillWidth: modelData.width === 0
                                    Layout.preferredWidth: modelData.width === 0 ? 200 : modelData.width
                                    text: {
                                        const value = rowLoader.model[modelData.role]
                                        return value === undefined || value === null ? "" : String(value)
                                    }
                                    color: modelData.role === "title" ? (rowLoader.model.missing ? Theme.danger : Theme.text)
                                          : modelData.role === "role" ? Theme.roleColor(rowLoader.model.role) : Theme.textDim
                                    font.pixelSize: modelData.role === "title" ? Theme.fontBody : Theme.fontSmall + 1
                                    font.weight: modelData.role === "title" ? Font.DemiBold : Font.Normal
                                    elide: Text.ElideRight
                                    rightPadding: 10
                                }
                            }
                        }
                    }
                }
            }
        }

        Text {
            Layout.topMargin: 6
            Layout.bottomMargin: 8
            visible: Object.keys(root.selection).filter(function (id) { return root.selection[id] }).length > 1
            text: qsTr("%1 selected · right-click for actions · Ctrl/Shift+click to change the selection")
                  .arg(Object.keys(root.selection).filter(function (id) { return root.selection[id] }).length)
            color: Theme.textDim
            font.pixelSize: Theme.fontSmall
        }
    }
}
