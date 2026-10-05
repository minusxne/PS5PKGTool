import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import PS5PkgTool.Native

// Edit files inside an exFAT or FFPKG image: queue changes, review them, apply in one task.
Item {
    id: editor
    property string source: ""
    property var entries: []
    property var pending: []
    property string folder: ""
    property string selected: ""
    property string filter: ""
    property bool loading: false
    signal closed()

    onSourceChanged: if (source.length > 0) load()

    function load() {
        loading = true
        pending = []
        folder = ""
        selected = ""
        App.call("editor.open", { source: source }, function (result) { entries = result.entries; loading = false },
                 function (e) { loading = false; App.showError(qsTr("Could not open the image"), e) })
    }

    readonly property var visibleEntries: {
        const prefix = folder.length > 0 ? folder + "/" : ""
        const needle = filter.toLowerCase()
        return entries.filter(function (e) {
            if (needle.length > 0) return e.path.toLowerCase().indexOf(needle) >= 0
            if (!e.path.startsWith(prefix)) return false
            return e.path.substring(prefix.length).indexOf("/") < 0 && e.path.length > prefix.length
        }).sort(function (a, b) { return a.isDirectory === b.isDirectory ? a.path.localeCompare(b.path) : (a.isDirectory ? -1 : 1) })
    }

    function queue(kind, imagePath, sourcePath) {
        pending = pending.concat([{ kind: kind, imagePath: imagePath, sourcePath: sourcePath || null }])
    }
    function targetPath(name) { return folder.length > 0 ? folder + "/" + name : name }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        RowLayout {
            IconButton { iconName: "back"; tip: qsTr("Back"); onClicked: editor.closed() }
            ColumnLayout {
                spacing: 0
                Text { text: qsTr("Edit image"); color: Theme.text; font.pixelSize: Theme.fontHeading; font.weight: Font.DemiBold }
                Text { text: editor.source; color: Theme.textFaint; font.pixelSize: Theme.fontSmall; elide: Text.ElideMiddle; Layout.maximumWidth: 700 }
            }
            Item { Layout.fillWidth: true }
            PsTextField { icon: "search"; clearable: true; placeholderText: qsTr("Find in image"); Layout.preferredWidth: 240; onTextChanged: editor.filter = text }
        }

        RowLayout {
            spacing: 8
            PsButton { compact: true; iconName: "back"; text: qsTr("Up"); enabled: editor.folder.length > 0; onClicked: { const i = editor.folder.lastIndexOf("/"); editor.folder = i < 0 ? "" : editor.folder.substring(0, i) } }
            Text { text: "/" + editor.folder; color: Theme.textDim; font.family: "monospace"; Layout.fillWidth: true; elide: Text.ElideMiddle }
            PsButton {
                compact: true; iconName: "convert"; text: qsTr("Replace selected…")
                enabled: editor.selected.length > 0 && !editor.entries.find(function (e) { return e.path === editor.selected && e.isDirectory })
                onClicked: App.pickFile(qsTr("Replacement for %1").arg(editor.selected), [], function (p) { editor.queue("replace", editor.selected, p) })
            }
            PsButton { compact: true; iconName: "add"; text: qsTr("Add file…"); onClicked: App.pickFile(qsTr("Add a file to /%1").arg(editor.folder), [], function (p) { editor.queue("addFile", editor.targetPath(Desktop.fileName(p)), p) }) }
            PsButton { compact: true; iconName: "folder-add"; text: qsTr("Add folder…"); onClicked: App.pickFolder(qsTr("Add a folder to /%1").arg(editor.folder), function (p) { editor.queue("addFolder", editor.targetPath(Desktop.fileName(p)), p) }) }
            PsButton { compact: true; iconName: "folder"; text: qsTr("New folder"); onClicked: App.prompt({ title: qsTr("New folder"), label: qsTr("Name"), confirmLabel: qsTr("Add"), onAccept: function (name) { editor.queue("mkdir", editor.targetPath(name)) } }) }
            PsButton { compact: true; iconName: "trash"; text: qsTr("Delete selected"); enabled: editor.selected.length > 0; onClicked: editor.queue("delete", editor.selected) }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16

            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 3
                ListView {
                    anchors.fill: parent
                    anchors.margins: 6
                    clip: true
                    model: editor.visibleEntries
                    ScrollBar.vertical: ScrollBar {}
                    delegate: Rectangle {
                        id: entryRow
                        required property var modelData
                        width: ListView.view.width
                        height: 38
                        radius: 8
                        color: editor.selected === modelData.path ? Theme.accentSoft : hover.hovered ? Theme.surfaceHover : "transparent"
                        HoverHandler { id: hover }
                        TapHandler {
                            onTapped: editor.selected = entryRow.modelData.path
                            onDoubleTapped: if (entryRow.modelData.isDirectory) { editor.folder = entryRow.modelData.path; editor.filter = "" }
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            Icon { name: entryRow.modelData.isDirectory ? "folder" : "file"; size: 16; color: entryRow.modelData.isDirectory ? Theme.accentBright : "white" }
                            Text { text: editor.filter.length > 0 ? entryRow.modelData.path : entryRow.modelData.path.split("/").pop(); color: Theme.text; font.pixelSize: Theme.fontSmall + 1; Layout.fillWidth: true; elide: Text.ElideMiddle }
                            Text { text: entryRow.modelData.isDirectory ? "" : Desktop.formatBytes(entryRow.modelData.size); color: Theme.textDim; font.pixelSize: Theme.fontSmall }
                        }
                    }
                }
                PsProgressBar { anchors.centerIn: parent; width: 200; indeterminate: true; visible: editor.loading }
            }

            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 2
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10
                    Text { text: qsTr("Pending changes (%1)").arg(editor.pending.length); color: Theme.text; font.weight: Font.DemiBold }
                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: editor.pending
                        spacing: 4
                        delegate: RowLayout {
                            id: change
                            required property var modelData
                            required property int index
                            width: ListView.view.width
                            Badge {
                                text: { const m = { replace: qsTr("Replace"), addFile: qsTr("Add"), addFolder: qsTr("Add folder"), mkdir: qsTr("New folder"), delete: qsTr("Delete") }; return m[change.modelData.kind] }
                                tint: change.modelData.kind === "delete" ? Theme.danger : change.modelData.kind === "replace" ? Theme.warning : Theme.success
                            }
                            Text { text: "/" + change.modelData.imagePath; color: Theme.text; font.pixelSize: Theme.fontSmall + 1; Layout.fillWidth: true; elide: Text.ElideMiddle }
                            IconButton { iconName: "close"; size: 26; onClicked: { const next = editor.pending.slice(); next.splice(change.index, 1); editor.pending = next } }
                        }
                    }
                    Text { visible: editor.pending.length === 0; text: qsTr("Nothing queued yet. Changes are applied together and verified before they replace the image."); color: Theme.textFaint; font.pixelSize: Theme.fontSmall + 1; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    RowLayout {
                        PsButton { text: qsTr("Undo last"); enabled: editor.pending.length > 0; onClicked: editor.pending = editor.pending.slice(0, -1) }
                        Item { Layout.fillWidth: true }
                        PsButton {
                            variant: "primary"
                            iconName: "check"
                            text: qsTr("Apply changes")
                            enabled: editor.pending.length > 0
                            onClicked: App.confirm({
                                title: qsTr("Apply %1 change(s)?").arg(editor.pending.length),
                                text: qsTr("The image is modified in place after the edited copy verifies."),
                                confirmLabel: qsTr("Apply"),
                                onAccept: function () {
                                    App.call("editor.apply", { source: editor.source, operations: editor.pending }, function () {
                                        editor.pending = []
                                        editor.closed()
                                        App.page = "tasks"
                                    }, function (e) { App.showError(qsTr("Could not apply"), e) })
                                }
                            })
                        }
                    }
                }
            }
        }
    }
}
