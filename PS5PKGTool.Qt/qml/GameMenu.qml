import QtQuick
import QtQuick.Controls.Basic
import PS5PkgTool.Native

// Right-click / ⋯ actions for one or more library items.
PsMenu {
    id: menu
    property var ids: []
    readonly property bool single: ids.length === 1
    readonly property var first: ids.length > 0 ? Library.row(ids[0]) : ({})
    readonly property bool buildable: single && ["Dump Files", "exFAT", "FFPKG", "FFPFSC"].indexOf(first.format) >= 0
    readonly property bool convertible: single && (buildable || first.format === "PKG")
    readonly property bool packages: ids.some(function (id) { return Library.row(id).format === "PKG" })

    function openFor(list) {
        ids = list.filter(function (id) { return !!id })
        if (ids.length > 0) popup()
    }

    PsMenuItem { text: qsTr("Details"); iconName: "info"; visible: menu.single; height: visible ? implicitHeight : 0; onTriggered: App.openDetails(menu.ids[0]) }
    PsMenuItem { text: qsTr("Show in file manager"); iconName: "folder"; visible: menu.single; height: visible ? implicitHeight : 0; onTriggered: App.revealItem(menu.ids[0]) }
    MenuSeparator {}
    PsMenuItem { text: qsTr("Convert…"); iconName: "convert"; enabled: menu.convertible; onTriggered: App.openTools(menu.ids[0], "convert", "") }
    PsMenuItem { text: qsTr("Build debug package…"); iconName: "package"; enabled: menu.buildable; onTriggered: App.openTools(menu.ids[0], "convert", "pkg") }
    PsMenuItem { text: qsTr("Extract…"); iconName: "extract"; enabled: menu.single && first.format !== "Dump Files"; onTriggered: App.openTools(menu.ids[0], "extract", "") }
    PsMenuItem { text: qsTr("Verify"); iconName: "verify"; enabled: menu.single && first.format !== "Dump Files"; onTriggered: App.openTools(menu.ids[0], "verify", "") }
    MenuSeparator {}
    PsMenu {
        title: qsTr("Copy")
        PsMenuItem { text: qsTr("Title"); onTriggered: App.copy(menu.ids.map(function (id) { return Library.row(id).title }).join("\n"), qsTr("Title")) }
        PsMenuItem { text: qsTr("Title ID"); onTriggered: App.copy(menu.ids.map(function (id) { return Library.row(id).titleId }).join("\n"), qsTr("Title ID")) }
        PsMenuItem { text: qsTr("Content ID"); onTriggered: App.copy(menu.ids.map(function (id) { return Library.row(id).contentId }).join("\n"), qsTr("Content ID")) }
        PsMenuItem { text: qsTr("File name"); onTriggered: App.copy(menu.ids.map(function (id) { return Library.row(id).fileName }).join("\n"), qsTr("File name")) }
        PsMenuItem { text: qsTr("Path"); onTriggered: App.copy(menu.ids.join("\n"), qsTr("Path")) }
    }
    PsMenu {
        title: qsTr("Rename")
        Repeater {
            model: App.renamePresets
            delegate: PsMenuItem { required property var modelData; text: modelData.label; onTriggered: App.rename(menu.ids, modelData.format, false, false) }
        }
        MenuSeparator {}
        PsMenuItem { text: qsTr("Custom (from Settings)"); onTriggered: App.rename(menu.ids, App.settings.renameFormat, false, false) }
        PsMenuItem { text: qsTr("By install order (packages)"); enabled: menu.packages; onTriggered: App.rename(menu.ids, App.settings.renameFormat, true, false) }
    }
    PsMenu {
        title: qsTr("Move to folder")
        PsMenuItem { text: qsTr("Grouped by title"); onTriggered: App.move(menu.ids, "title") }
        PsMenuItem { text: qsTr("Grouped by title ID"); onTriggered: App.move(menu.ids, "titleid") }
        PsMenuItem { text: qsTr("Grouped by category"); onTriggered: App.move(menu.ids, "category") }
        PsMenuItem { text: qsTr("Grouped by region"); onTriggered: App.move(menu.ids, "region") }
        PsMenuItem { text: qsTr("Grouped by format"); onTriggered: App.move(menu.ids, "source") }
        PsMenuItem { text: qsTr("All into one folder"); onTriggered: App.move(menu.ids, "flat") }
    }
    PsMenuItem { text: qsTr("Save artwork…"); iconName: "image"; onTriggered: App.saveArtwork(menu.ids) }
    PsMenuItem { text: qsTr("Export as CSV…"); iconName: "export"; onTriggered: App.exportCsv(menu.ids) }
    MenuSeparator {}
    PsMenuItem {
        text: App.settings.permanentDelete ? qsTr("Delete permanently…") : qsTr("Move to trash…")
        iconName: "trash"
        onTriggered: App.remove(menu.ids)
    }
}
