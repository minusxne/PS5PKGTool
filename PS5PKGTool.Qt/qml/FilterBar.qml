import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import PS5PkgTool.Native

// Search, quick filters, sort/group, saved views and library actions above every library view.
ColumnLayout {
    id: bar
    spacing: 10

    readonly property var presets: ["All", "Games", "Updates", "DLC", "Dumps", "PKG", "exFAT", "FFPKG", "FFPFSC"]

    function presetActive(name) {
        const c = App.categories, f = App.formats
        const noQuery = App.query.length === 0 && App.regions.length === 0
        switch (name) {
        case "All": return !App.hasFilters()
        case "Games": return noQuery && f.length === 0 && c.length === 1 && c[0] === "Game"
        case "Updates": return noQuery && f.length === 0 && c.length === 1 && c[0] === "Patch"
        case "DLC": return noQuery && f.length === 0 && c.length === 1 && c[0] === "DLC"
        case "Dumps": return noQuery && c.length === 0 && f.length === 1 && f[0] === "Dump Files"
        default: return noQuery && c.length === 0 && f.length === 1 && f[0] === name
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        PsTextField {
            id: search
            Layout.fillWidth: true
            Layout.minimumWidth: 220
            Layout.maximumWidth: 460
            icon: "search"
            clearable: true
            placeholderText: qsTr("Search titles, IDs, paths…  try  size:>50GB  or  category:patch")
            text: App.query
            onTextEdited: App.query = text
            Keys.onEscapePressed: { text = ""; App.query = ""; focus = false }
            Keys.onDownPressed: hintPopup.open()
            Connections {
                target: App
                function onSearchFocusRequested() { search.forceActiveFocus(); search.selectAll() }
                function onQueryChanged() { if (search.text !== App.query) search.text = App.query }
            }
            onActiveFocusChanged: if (activeFocus && text.length === 0) hintPopup.open()

            Popup {
                id: hintPopup
                y: search.height + 6
                width: 520
                padding: 14
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                background: Rectangle { radius: Theme.radius; color: Theme.surfaceRaised; border.color: Theme.outline }
                contentItem: ColumnLayout {
                    spacing: 6
                    Text { text: qsTr("Search fields"); color: Theme.text; font.weight: Font.DemiBold; font.pixelSize: Theme.fontBody }
                    Text {
                        text: qsTr("Words must all match. Use quotes for phrases, - to exclude, | for either, = for exact.")
                        color: Theme.textFaint; font.pixelSize: Theme.fontSmall; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                    Repeater {
                        model: App.queryHelp.fields
                        delegate: Rectangle {
                            id: hint
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 30
                            radius: 6
                            color: hintHover.hovered ? Theme.surfaceHover : "transparent"
                            HoverHandler { id: hintHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    search.text = (search.text.length > 0 ? search.text + " " : "") + hint.modelData.example
                                    App.query = search.text
                                    search.forceActiveFocus()
                                }
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                Text { text: hint.modelData.example; color: Theme.accentBright; font.family: "monospace"; font.pixelSize: Theme.fontSmall + 1; Layout.preferredWidth: 200 }
                                Text { text: hint.modelData.help; color: Theme.textDim; font.pixelSize: Theme.fontSmall + 1; Layout.fillWidth: true; elide: Text.ElideRight }
                            }
                        }
                    }
                }
            }
        }

        Badge {
            visible: Library.warning.length > 0
            text: qsTr("Check query")
            tint: Theme.warning
            icon: "warning"
            ToolTip.visible: warnHover.hovered
            ToolTip.text: Library.warning
            HoverHandler { id: warnHover }
        }

        Text {
            text: Library.visibleCount === Library.totalCount ? qsTr("%1 items").arg(Library.totalCount)
                                                              : qsTr("%1 of %2").arg(Library.visibleCount).arg(Library.totalCount)
            color: Theme.textDim
            font.pixelSize: Theme.fontSmall + 1
        }

        Item { Layout.fillWidth: true }

        PsButton {
            compact: true
            iconName: "filter"
            text: App.categories.length + App.regions.length + App.formats.length > 0
                  ? qsTr("Filters · %1").arg(App.categories.length + App.regions.length + App.formats.length) : qsTr("Filters")
            onClicked: filterPopup.open()
            FilterPopup { id: filterPopup; y: parent.height + 6 }
        }
        PsButton {
            compact: true
            iconName: "sort"
            text: qsTr("Sort")
            onClicked: sortMenu.popup()
            PsMenu {
                id: sortMenu
                Repeater {
                    model: [["Title", qsTr("Title")], ["TitleId", qsTr("Title ID")], ["Size", qsTr("Size")], ["Version", qsTr("Version")],
                            ["Firmware", qsTr("Required firmware")], ["Category", qsTr("Category")], ["Role", qsTr("Role")],
                            ["Region", qsTr("Region")], ["Source", qsTr("Format")], ["Location", qsTr("Location")]]
                    delegate: PsMenuItem {
                        required property var modelData
                        readonly property string state: {
                            for (let i = 0; i < App.sortKeys.length; ++i)
                                if (App.sortKeys[i].split(":")[0] === modelData[0]) return App.sortKeys[i].split(":")[1]
                            return ""
                        }
                        text: modelData[1] + (state === "asc" ? "  ↑" : state === "desc" ? "  ↓" : "")
                        checkable: true
                        checked: state.length > 0
                        onTriggered: App.setSort(modelData[0], false)
                    }
                }
            }
        }
        PsButton {
            compact: true
            iconName: "layers"
            text: App.groupBy.length > 0 ? qsTr("Group · %1").arg(groupLabel(App.groupBy)) : qsTr("Group")
            visible: App.viewMode === "list"
            function groupLabel(key) {
                return { family: qsTr("Family"), titleid: qsTr("Title ID"), category: qsTr("Category"), region: qsTr("Region"),
                         source: qsTr("Format"), firmware: qsTr("Firmware") }[key] || key
            }
            onClicked: groupMenu.popup()
            PsMenu {
                id: groupMenu
                Repeater {
                    model: [["", qsTr("No grouping")], ["family", qsTr("Family (base, updates, DLC)")], ["titleid", qsTr("Title ID")],
                            ["category", qsTr("Category")], ["region", qsTr("Region")], ["source", qsTr("Format")], ["firmware", qsTr("Required firmware")]]
                    delegate: PsMenuItem {
                        required property var modelData
                        text: modelData[1]
                        checkable: true
                        checked: App.groupBy === modelData[0]
                        onTriggered: App.groupBy = modelData[0]
                    }
                }
            }
        }

        // View switcher
        Rectangle {
            implicitWidth: viewRow.implicitWidth + 8
            implicitHeight: 40
            radius: 20
            color: Qt.rgba(1, 1, 1, 0.07)
            Row {
                id: viewRow
                anchors.centerIn: parent
                spacing: 2
                IconButton { iconName: "rail"; size: 34; active: App.viewMode === "rail"; tip: qsTr("Home"); onClicked: App.setSetting("viewMode", "rail") }
                IconButton { iconName: "grid"; size: 34; active: App.viewMode === "grid"; tip: qsTr("Game library"); onClicked: App.setSetting("viewMode", "grid") }
                IconButton { iconName: "list"; size: 34; active: App.viewMode === "list"; tip: qsTr("List"); onClicked: App.setSetting("viewMode", "list") }
            }
        }

        IconButton { iconName: "folder-add"; tip: qsTr("Add library folder"); onClicked: App.pickFolder(qsTr("Add a library folder"), function (path) { App.addFolder(path) }) }
        IconButton { iconName: "refresh"; tip: qsTr("Refresh library (F5)"); enabled: !App.scanning; onClicked: App.scan() }
        IconButton {
            iconName: "more"
            tip: qsTr("More")
            onClicked: libraryMenu.popup()
            PsMenu {
                id: libraryMenu
                PsMenuItem { text: qsTr("Open dump folder…"); iconName: "folder"; onTriggered: App.pickFolder(qsTr("Open a dump folder"), function (path) { App.openPath(path) }) }
                PsMenuItem { text: qsTr("Open package or image…"); iconName: "package"; onTriggered: App.pickFile(qsTr("Open a package or image"), ["PS5 sources (*.pkg *.exfat *.ffpkg *.ffpfsc)"], function (path) { App.openPath(path) }) }
                MenuSeparator {}
                PsMenu {
                    title: qsTr("Saved views")
                    PsMenuItem {
                        text: qsTr("Save current view…")
                        iconName: "add"
                        onTriggered: App.prompt({
                            title: qsTr("Save view"), label: qsTr("Name"), value: "",
                            onAccept: function (name) {
                                const view = App.viewRequest()
                                view.name = name
                                App.call("views.save", { view: view }, function () { App.toast(qsTr("View saved"), name, "success", "check") })
                            }
                        })
                    }
                    Repeater {
                        model: App.settings.savedViews || []
                        delegate: PsMenuItem {
                            required property var modelData
                            text: modelData.name
                            iconName: "eye"
                            onTriggered: App.applySavedView(modelData)
                        }
                    }
                    PsMenu {
                        title: qsTr("Delete a view")
                        enabled: (App.settings.savedViews || []).length > 0
                        Repeater {
                            model: App.settings.savedViews || []
                            delegate: PsMenuItem {
                                required property var modelData
                                text: modelData.name
                                iconName: "trash"
                                onTriggered: App.call("views.delete", { name: modelData.name })
                            }
                        }
                    }
                }
                PsMenuItem { text: qsTr("Find duplicates"); iconName: "duplicate"; onTriggered: App.findDuplicates() }
                PsMenuItem { text: qsTr("Updates without base game"); iconName: "layers"; onTriggered: App.missingBase() }
                PsMenuItem { text: qsTr("Export visible items (CSV)…"); iconName: "export"; onTriggered: App.exportCsv(Library.visibleIds()) }
                PsMenuItem { text: qsTr("Export whole library (CSV)…"); iconName: "export"; onTriggered: App.exportCsv([]) }
                PsMenu {
                    title: qsTr("Rename every item")
                    Repeater {
                        model: App.renamePresets
                        delegate: PsMenuItem { required property var modelData; text: modelData.label; onTriggered: App.rename([], modelData.format, false, true) }
                    }
                    PsMenuItem { text: qsTr("Custom (from Settings)"); onTriggered: App.rename([], App.settings.renameFormat, false, true) }
                }
                MenuSeparator {}
                PsMenuItem { text: qsTr("Remove missing items"); iconName: "broom"; onTriggered: App.call("library.removeMissing", {}, function (r) { App.toast(qsTr("Cleaned up"), qsTr("%1 missing item(s) removed").arg(r.removed), "success", "broom") }) }
                PsMenuItem {
                    text: qsTr("Empty the list")
                    iconName: "trash"
                    onTriggered: App.confirm({
                        title: qsTr("Empty the library list?"),
                        text: qsTr("The cached list is cleared until the next refresh. Files on disk are not touched."),
                        confirmLabel: qsTr("Empty list"),
                        onAccept: function () { App.call("library.clear") }
                    })
                }
            }
        }
    }

    // Quick presets and active filter chips
    FlowRow {
        Layout.fillWidth: true
        spacing: 8
        Repeater {
            model: bar.presets
            delegate: Chip {
                required property string modelData
                text: modelData === "All" ? qsTr("All") : modelData === "Updates" ? qsTr("Updates") : modelData === "Games" ? qsTr("Games") : modelData
                selected: bar.presetActive(modelData)
                count: modelData === "All" ? Library.totalCount : -1
                onClicked: App.applyPreset(modelData)
            }
        }
        Rectangle { width: 1; height: 24; color: Theme.outline; visible: regionChips.count > 0 || queryChip.visible }
        Repeater {
            id: regionChips
            model: App.regions
            delegate: Chip {
                required property string modelData
                text: modelData
                iconName: "globe"
                selected: true
                removable: true
                onRemoved: App.regions = App.toggleValue(App.regions, modelData)
                onClicked: App.regions = App.toggleValue(App.regions, modelData)
            }
        }
        Chip {
            id: queryChip
            visible: App.query.length > 0
            text: "“" + App.query + "”"
            iconName: "search"
            selected: true
            removable: true
            onRemoved: App.query = ""
            onClicked: App.query = ""
        }
    }
}
