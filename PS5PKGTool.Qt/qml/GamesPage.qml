import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import PS5PkgTool.Native

// The library: a PS5-style home rail with a hero panel, a game-library grid, or a dense list.
FocusScope {
    id: page
    focus: true

    readonly property bool hasSources: (App.settings.libraryFolders || []).length > 0 || (App.settings.manualSources || []).length > 0
    readonly property bool empty: Library.totalCount === 0
    readonly property bool filteredEmpty: !empty && Library.visibleCount === 0

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.padLarge
        anchors.rightMargin: Theme.padLarge
        spacing: 14

        FilterBar {
            id: filterBar
            Layout.fillWidth: true
            visible: !page.empty
        }

        Loader {
            Layout.fillWidth: true
            Layout.fillHeight: true
            active: !page.empty && !page.filteredEmpty
            sourceComponent: App.viewMode === "grid" ? gridView : App.viewMode === "list" ? listView : railView
            focus: true
        }

        // First run: nothing configured yet.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: page.empty
            EmptyState {
                anchors.centerIn: parent
                icon: page.hasSources ? "search" : "games"
                title: !App.libraryLoaded ? "" : page.hasSources ? (App.scanning ? qsTr("Scanning your library…") : qsTr("No games found yet"))
                                                                 : qsTr("Welcome to PS5 PKG Tool")
                text: page.hasSources
                      ? qsTr("Your library folders don't contain any PS5 dumps, packages or images yet. Add another folder, or refresh after copying games in.")
                      : qsTr("Point the tool at the folders where you keep PS5 dumps (folders with sce_sys/param.json), .pkg packages and exFAT, FFPKG or FFPFSC images. Everything is read in place; nothing is modified until you ask.")
                PsButton {
                    variant: "primary"
                    iconName: "folder-add"
                    text: qsTr("Add library folder")
                    onClicked: App.pickFolder(qsTr("Add a library folder"), function (path) { App.addFolder(path) })
                }
                PsButton {
                    iconName: "folder"
                    text: qsTr("Open one item")
                    onClicked: openMenu.popup()
                    PsMenu {
                        id: openMenu
                        PsMenuItem { text: qsTr("Dump folder…"); iconName: "folder"; onTriggered: App.pickFolder(qsTr("Open a dump folder"), function (path) { App.openPath(path) }) }
                        PsMenuItem { text: qsTr("Package or image…"); iconName: "package"; onTriggered: App.pickFile(qsTr("Open a package or image"), ["PS5 sources (*.pkg *.exfat *.ffpkg *.ffpfsc)"], function (path) { App.openPath(path) }) }
                    }
                }
                PsButton { visible: page.hasSources; iconName: "refresh"; text: qsTr("Refresh"); enabled: !App.scanning; onClicked: App.scan() }
            }
        }

        // Filters hide everything.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: page.filteredEmpty
            EmptyState {
                anchors.centerIn: parent
                icon: "filter"
                title: qsTr("Nothing matches")
                text: Library.warning.length > 0 ? qsTr("Check your search: %1").arg(Library.warning)
                                                 : qsTr("No item matches the current search and filters.")
                PsButton { variant: "primary"; text: qsTr("Clear filters"); onClicked: App.clearFilters() }
            }
        }
    }

    Component { id: railView; HomeRail {} }
    Component { id: gridView; LibraryGrid {} }
    Component { id: listView; LibraryList {} }
}
