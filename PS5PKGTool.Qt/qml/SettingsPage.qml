import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import PS5PkgTool.Native

// PS5-style settings: categories on the left, the selected category on the right. Every change
// is saved immediately.
FocusScope {
    id: page
    property string section: "library"
    property var cacheInfo: null
    property string renameExample: ""
    property var unknownTokens: []

    readonly property var sections: [
        { key: "library", label: qsTr("Library"), icon: "games", hint: qsTr("Folders and scanning") },
        { key: "appearance", label: qsTr("Appearance"), icon: "palette", hint: qsTr("Views, art and motion") },
        { key: "naming", label: qsTr("Naming"), icon: "rename", hint: qsTr("Rename format") },
        { key: "viewing", label: qsTr("Viewing & cache"), icon: "eye", hint: qsTr("Previews and artwork cache") },
        { key: "output", label: qsTr("Output & defaults"), icon: "package", hint: qsTr("Builder, passcode, output folder") },
        { key: "files", label: qsTr("File operations"), icon: "folder", hint: qsTr("Confirmations and deletion") },
        { key: "maintenance", label: qsTr("Maintenance"), icon: "repair", hint: qsTr("Import, export, reset, logs") },
        { key: "about", label: qsTr("About"), icon: "info", hint: qsTr("Version and credits") }
    ]

    function refreshExample(format) {
        App.call("settings.renameExample", { format: format, id: App.selectedId }, function (r) { renameExample = r.example; unknownTokens = r.unknownTokens })
    }
    onSectionChanged: {
        if (section === "naming") refreshExample(App.settings.renameFormat)
        if (section === "viewing" || section === "maintenance") App.call("app.cacheInfo", {}, function (r) { cacheInfo = r })
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.padLarge
        anchors.rightMargin: Theme.padLarge
        anchors.bottomMargin: 20
        spacing: 28

        ListView {
            Layout.preferredWidth: 300
            Layout.fillHeight: true
            model: page.sections
            spacing: 4
            interactive: false
            delegate: AbstractButton {
                id: entry
                required property var modelData
                readonly property bool active: page.section === modelData.key
                width: ListView.view.width
                height: 62
                hoverEnabled: true
                focusPolicy: Qt.StrongFocus
                onClicked: page.section = modelData.key
                background: Rectangle {
                    radius: Theme.radius
                    color: entry.active ? "#ffffff" : entry.hovered ? Theme.surfaceHover : "transparent"
                    border.width: entry.visualFocus ? 2 : 0
                    border.color: Theme.accentBright
                }
                contentItem: RowLayout {
                    spacing: 14
                    Item { implicitWidth: 2 }
                    Icon { name: entry.modelData.icon; size: 22; color: entry.active ? "#0b0e14" : "white" }
                    ColumnLayout {
                        spacing: 1
                        Layout.fillWidth: true
                        Text { text: entry.modelData.label; color: entry.active ? "#0b0e14" : Theme.text; font.pixelSize: Theme.fontBody + 1; font.weight: Font.DemiBold }
                        Text { text: entry.modelData.hint; color: entry.active ? Qt.rgba(0, 0, 0, 0.55) : Theme.textFaint; font.pixelSize: Theme.fontSmall }
                    }
                }
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: panel.implicitHeight + 40
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            ColumnLayout {
                id: panel
                width: Math.min(parent.width - 16, 860)
                spacing: 14

                Text { text: page.sections.find(function (s) { return s.key === page.section }).label; color: Theme.text; font.pixelSize: Theme.fontTitle; font.weight: Font.Light; Layout.bottomMargin: 6 }

                // ------------------------------------------------ Library
                ColumnLayout {
                    visible: page.section === "library"
                    Layout.fillWidth: true
                    spacing: 14
                    Card {
                        Layout.fillWidth: true
                        implicitHeight: foldersColumn.implicitHeight + 32
                        ColumnLayout {
                            id: foldersColumn
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 8
                            RowLayout {
                                Text { text: qsTr("Library folders"); color: Theme.text; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                PsButton { compact: true; iconName: "folder-add"; text: qsTr("Add folder…"); onClicked: App.pickFolder(qsTr("Add a library folder"), function (p) { App.addFolder(p) }) }
                            }
                            Text { visible: (App.settings.libraryFolders || []).length === 0; text: qsTr("No folders yet."); color: Theme.textFaint }
                            Repeater {
                                model: App.settings.libraryFolders || []
                                delegate: RowLayout {
                                    required property string modelData
                                    Layout.fillWidth: true
                                    Icon { name: "folder"; size: 16; color: Theme.accentBright }
                                    Text { text: modelData; color: Theme.text; elide: Text.ElideMiddle; Layout.fillWidth: true }
                                    Text { text: Desktop.freeSpaceText(modelData); color: Theme.textFaint; font.pixelSize: Theme.fontSmall }
                                    IconButton { iconName: "folder"; size: 30; tip: qsTr("Open"); onClicked: Desktop.openPath(modelData) }
                                    IconButton { iconName: "close"; size: 30; tip: qsTr("Remove from the library (files stay on disk)"); onClicked: App.call("library.removeFolder", { path: modelData }) }
                                }
                            }
                        }
                    }
                    Card {
                        Layout.fillWidth: true
                        implicitHeight: sourcesColumn.implicitHeight + 32
                        ColumnLayout {
                            id: sourcesColumn
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 8
                            Text { text: qsTr("Single items opened outside the library folders"); color: Theme.text; font.weight: Font.DemiBold }
                            Text { visible: (App.settings.manualSources || []).length === 0; text: qsTr("None. Items you open with Ctrl+O, drag and drop or the command line appear here."); color: Theme.textFaint; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            Repeater {
                                model: App.settings.manualSources || []
                                delegate: RowLayout {
                                    required property string modelData
                                    Layout.fillWidth: true
                                    Icon { name: Desktop.isDir(modelData) ? "folder" : "file"; size: 16 }
                                    Text { text: modelData; color: Theme.text; elide: Text.ElideMiddle; Layout.fillWidth: true }
                                    IconButton { iconName: "close"; size: 30; tip: qsTr("Forget"); onClicked: App.call("library.removeSource", { path: modelData }) }
                                }
                            }
                        }
                    }
                    PsSwitch { Layout.fillWidth: true; text: qsTr("Scan subfolders"); description: qsTr("Look inside every folder below each library folder."); checked: App.settings.recursiveScan !== false; onToggled: App.setSetting("recursiveScan", checked) }
                    PsSwitch { Layout.fillWidth: true; text: qsTr("Refresh the library at startup"); description: qsTr("Otherwise the cached list loads instantly and you refresh with F5."); checked: !!App.settings.refreshOnStartup; onToggled: App.setSetting("refreshOnStartup", checked) }
                    RowLayout {
                        PsButton { iconName: "refresh"; text: qsTr("Refresh now"); enabled: !App.scanning; onClicked: App.scan() }
                        PsButton { iconName: "broom"; text: qsTr("Clear recent folders"); enabled: (App.settings.recentFolders || []).length > 0; onClicked: App.call("library.clearRecent") }
                    }
                }

                // ------------------------------------------------ Appearance
                ColumnLayout {
                    visible: page.section === "appearance"
                    Layout.fillWidth: true
                    spacing: 14
                    RowLayout {
                        spacing: 12
                        Repeater {
                            model: [["rail", "rail", qsTr("Home"), qsTr("A row of tiles with the focused title's details, like the console home screen.")],
                                    ["grid", "grid", qsTr("Game library"), qsTr("All items as tiles with titles.")],
                                    ["list", "list", qsTr("List"), qsTr("Dense, sortable, groupable, with multi-select.")]]
                            delegate: AbstractButton {
                                id: viewChoice
                                required property var modelData
                                readonly property bool active: (App.settings.viewMode || "rail") === modelData[0]
                                Layout.fillWidth: true
                                Layout.preferredHeight: 128
                                hoverEnabled: true
                                onClicked: App.setSetting("viewMode", modelData[0])
                                background: Rectangle { radius: Theme.radiusLarge; color: viewChoice.active ? Theme.accentSoft : viewChoice.hovered ? Theme.surfaceHover : Theme.surface; border.width: viewChoice.active ? 2 : 1; border.color: viewChoice.active ? Theme.accentBright : Theme.outline }
                                contentItem: ColumnLayout {
                                    spacing: 6
                                    Icon { name: viewChoice.modelData[1]; size: 26; Layout.leftMargin: 8; Layout.topMargin: 6 }
                                    Text { text: viewChoice.modelData[2]; color: Theme.text; font.weight: Font.DemiBold; Layout.leftMargin: 8 }
                                    Text { text: viewChoice.modelData[3]; color: Theme.textDim; font.pixelSize: Theme.fontSmall; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.leftMargin: 8; Layout.rightMargin: 8 }
                                }
                            }
                        }
                    }
                    PsSwitch { Layout.fillWidth: true; text: qsTr("Show key art in the background"); description: qsTr("The selected title's artwork fills the window behind the interface."); checked: App.settings.backgroundArt !== false; onToggled: App.setSetting("backgroundArt", checked) }
                    RowLayout {
                        enabled: App.settings.backgroundArt !== false
                        Text { text: qsTr("Background blur"); color: Theme.text; Layout.preferredWidth: 200 }
                        Slider { from: 0; to: 64; stepSize: 1; value: App.settings.backgroundBlur || 0; Layout.fillWidth: true; onMoved: blurTimer.restart() ; id: blurSlider }
                        Text { text: Math.round(blurSlider.value); color: Theme.textDim; Layout.preferredWidth: 40 }
                        Timer { id: blurTimer; interval: 250; onTriggered: App.setSetting("backgroundBlur", Math.round(blurSlider.value)) }
                    }
                    RowLayout {
                        enabled: App.settings.backgroundArt !== false
                        Text { text: qsTr("Background brightness"); color: Theme.text; Layout.preferredWidth: 200 }
                        Slider { id: opacitySlider; from: 10; to: 100; stepSize: 1; value: App.settings.backgroundOpacity || 55; Layout.fillWidth: true; onMoved: opacityTimer.restart() }
                        Text { text: Math.round(opacitySlider.value) + "%"; color: Theme.textDim; Layout.preferredWidth: 40 }
                        Timer { id: opacityTimer; interval: 250; onTriggered: App.setSetting("backgroundOpacity", Math.round(opacitySlider.value)) }
                    }
                    PsSwitch { Layout.fillWidth: true; text: qsTr("Reduce motion"); description: qsTr("Turn off zoom, slide and fade animations."); checked: !!App.settings.reduceMotion; onToggled: App.setSetting("reduceMotion", checked) }
                    PsSwitch { Layout.fillWidth: true; text: qsTr("Show thumbnails in the list"); checked: App.settings.showThumbnails !== false; onToggled: App.setSetting("showThumbnails", checked) }
                    RowLayout {
                        Text { text: qsTr("List density"); color: Theme.text; Layout.preferredWidth: 200 }
                        Repeater {
                            model: [[18, qsTr("Compact")], [22, qsTr("Normal")], [28, qsTr("Comfortable")]]
                            delegate: Chip { required property var modelData; text: modelData[1]; selected: (App.settings.gridRowHeight || 22) === modelData[0]; onClicked: App.setSetting("gridRowHeight", modelData[0]) }
                        }
                    }
                    RowLayout {
                        Text { text: qsTr("Default grouping (list)"); color: Theme.text; Layout.preferredWidth: 200 }
                        PsComboBox {
                            model: [qsTr("None"), qsTr("Family"), qsTr("Title ID"), qsTr("Category"), qsTr("Region"), qsTr("Format"), qsTr("Firmware")]
                            currentIndex: Math.max(0, ["", "family", "titleid", "category", "region", "source", "firmware"].indexOf(App.settings.defaultGroupBy || ""))
                            onActivated: (i) => App.setSetting("defaultGroupBy", ["", "family", "titleid", "category", "region", "source", "firmware"][i])
                        }
                    }
                    PsSwitch { Layout.fillWidth: true; text: qsTr("Notify when a task finishes"); checked: App.settings.notifyOnTaskFinish !== false; onToggled: App.setSetting("notifyOnTaskFinish", checked) }
                }

                // ------------------------------------------------ Naming
                ColumnLayout {
                    visible: page.section === "naming"
                    Layout.fillWidth: true
                    spacing: 12
                    Text { text: qsTr("Used by Rename › Custom and by rename by install order. Empty [ ] and ( ) groups are dropped, and characters that are invalid on Windows or exFAT drives become _."); color: Theme.textDim; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    PsTextField {
                        id: formatField
                        Layout.fillWidth: true
                        text: App.settings.renameFormat || ""
                        font.family: "monospace"
                        onTextEdited: { page.refreshExample(text); formatTimer.restart() }
                        Timer { id: formatTimer; interval: 600; onTriggered: App.setSetting("renameFormat", formatField.text) }
                    }
                    Card {
                        Layout.fillWidth: true
                        implicitHeight: 64
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            Text { text: qsTr("Example"); color: Theme.textDim; Layout.preferredWidth: 90 }
                            Text { text: page.renameExample; color: Theme.text; font.pixelSize: Theme.fontBody + 1; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                        }
                    }
                    RowLayout {
                        visible: page.unknownTokens.length > 0
                        Icon { name: "warning"; color: Theme.warning; size: 16 }
                        Text { text: qsTr("Unknown tokens: %1").arg(page.unknownTokens.join(", ")); color: Theme.warning }
                    }
                    Text { text: qsTr("Insert a token"); color: Theme.textDim; font.pixelSize: Theme.fontSmall; font.weight: Font.DemiBold; Layout.topMargin: 6 }
                    FlowRow {
                        Layout.fillWidth: true
                        spacing: 8
                        Repeater {
                            model: App.renameTokens
                            delegate: Chip {
                                required property string modelData
                                text: modelData
                                onClicked: { formatField.insert(formatField.cursorPosition, modelData); page.refreshExample(formatField.text); formatTimer.restart() }
                            }
                        }
                    }
                    Text { text: qsTr("Start from a preset"); color: Theme.textDim; font.pixelSize: Theme.fontSmall; font.weight: Font.DemiBold; Layout.topMargin: 6 }
                    FlowRow {
                        Layout.fillWidth: true
                        spacing: 8
                        Repeater {
                            model: App.renamePresets
                            delegate: Chip {
                                required property var modelData
                                text: modelData.label
                                onClicked: { formatField.text = modelData.format; page.refreshExample(modelData.format); App.setSetting("renameFormat", modelData.format) }
                            }
                        }
                    }
                }

                // ------------------------------------------------ Viewing & cache
                ColumnLayout {
                    visible: page.section === "viewing"
                    Layout.fillWidth: true
                    spacing: 14
                    PsSwitch { Layout.fillWidth: true; text: qsTr("Show the file preview pane"); description: qsTr("In the Files tab of the details page."); checked: App.settings.showFilePreview !== false; onToggled: App.setSetting("showFilePreview", checked) }
                    RowLayout {
                        Text { text: qsTr("Largest file to preview"); color: Theme.text; Layout.preferredWidth: 260 }
                        PsSpinBox { from: 1; to: 1024; value: App.settings.maxPreviewMb || 16; textFromValue: function (v) { return v + " MiB" }; valueFromText: function (t) { return parseInt(t) }; onValueModified: App.setSetting("maxPreviewMb", value) }
                    }
                    RowLayout {
                        Text { text: qsTr("Hex view page size"); color: Theme.text; Layout.preferredWidth: 260 }
                        PsSpinBox { from: 1; to: 256; value: App.settings.hexPageKb || 16; textFromValue: function (v) { return v + " KiB" }; valueFromText: function (t) { return parseInt(t) }; onValueModified: App.setSetting("hexPageKb", value) }
                    }
                    Card {
                        Layout.fillWidth: true
                        implicitHeight: 84
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 18
                            ColumnLayout {
                                Layout.fillWidth: true
                                Text { text: qsTr("Artwork and preview cache"); color: Theme.text; font.weight: Font.DemiBold }
                                Text { text: page.cacheInfo ? page.cacheInfo.artworkText + " · " + page.cacheInfo.directory : ""; color: Theme.textFaint; font.pixelSize: Theme.fontSmall; elide: Text.ElideMiddle; Layout.fillWidth: true }
                            }
                            PsButton { iconName: "broom"; text: qsTr("Clear caches"); onClicked: App.call("app.clearCaches", {}, function () { App.call("app.cacheInfo", {}, function (r) { page.cacheInfo = r }); App.toast(qsTr("Caches cleared"), "", "success", "broom") }) }
                        }
                    }
                }

                // ------------------------------------------------ Output & defaults
                ColumnLayout {
                    visible: page.section === "output"
                    Layout.fillWidth: true
                    spacing: 14
                    Text { text: qsTr("Default output folder"); color: Theme.text; font.weight: Font.DemiBold }
                    Text { text: qsTr("Suggested outputs go here. Leave empty to put them next to the source."); color: Theme.textFaint; font.pixelSize: Theme.fontSmall }
                    RowLayout {
                        Layout.fillWidth: true
                        PsTextField { id: outputField; Layout.fillWidth: true; text: App.settings.outputDirectory || ""; placeholderText: qsTr("Next to the source"); onEditingFinished: App.setSetting("outputDirectory", text) }
                        PsButton { compact: true; iconName: "folder"; text: qsTr("Browse…"); onClicked: App.pickFolder(qsTr("Default output folder"), function (p) { App.setSetting("outputDirectory", p) }) }
                        PsButton { compact: true; iconName: "close"; text: qsTr("Clear"); enabled: (App.settings.outputDirectory || "").length > 0; onClicked: App.setSetting("outputDirectory", "") }
                    }
                    Text { text: qsTr("Default package builder"); color: Theme.text; font.weight: Font.DemiBold; Layout.topMargin: 8 }
                    Repeater {
                        model: App.buildOptions ? App.buildOptions.builders : []
                        delegate: AbstractButton {
                            id: builderChoice
                            required property var modelData
                            readonly property bool active: (App.settings.buildBackend || (App.buildOptions ? App.buildOptions.defaultBackend : "")) === modelData.id
                            Layout.fillWidth: true
                            implicitHeight: 72
                            enabled: modelData.available
                            hoverEnabled: true
                            onClicked: App.setSetting("buildBackend", modelData.id, function () { App.call("tools.buildOptions", {}, function (r) { App.buildOptions = r }) })
                            background: Rectangle { radius: Theme.radius; color: builderChoice.active ? Theme.accentSoft : builderChoice.hovered ? Theme.surfaceHover : Theme.surface; border.width: builderChoice.active ? 2 : 1; border.color: builderChoice.active ? Theme.accentBright : Theme.outline; opacity: builderChoice.enabled ? 1 : 0.5 }
                            contentItem: RowLayout {
                                spacing: 12
                                Icon { name: builderChoice.active ? "check-circle" : "package"; size: 22; color: builderChoice.active ? Theme.accentBright : "white"; Layout.leftMargin: 8 }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text { text: builderChoice.modelData.name; color: Theme.text; font.weight: Font.DemiBold }
                                    Text { text: builderChoice.modelData.available ? builderChoice.modelData.note : builderChoice.modelData.reason; color: Theme.textDim; font.pixelSize: Theme.fontSmall; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                }
                            }
                        }
                    }
                    Text { text: qsTr("Default debug passcode"); color: Theme.text; font.weight: Font.DemiBold; Layout.topMargin: 8 }
                    Text { text: qsTr("Blank uses the standard all-zero passcode. Otherwise exactly 32 printable characters."); color: Theme.textFaint; font.pixelSize: Theme.fontSmall }
                    RowLayout {
                        PsTextField {
                            id: passcodeField
                            Layout.preferredWidth: 420
                            text: App.settings.debugPasscode || ""
                            echoMode: showPasscode.checked ? TextInput.Normal : TextInput.Password
                            font.family: "monospace"
                            maximumLength: 32
                            placeholderText: "00000000000000000000000000000000"
                        }
                        PsCheckBox { id: showPasscode; text: qsTr("Show") }
                        PsButton {
                            compact: true
                            text: qsTr("Save")
                            enabled: passcodeField.text !== (App.settings.debugPasscode || "") && (passcodeField.text.length === 0 || passcodeField.text.length === 32)
                            onClicked: App.setSetting("debugPasscode", passcodeField.text, function () { App.toast(qsTr("Passcode saved"), "", "success", "lock") })
                        }
                        Text { visible: passcodeField.text.length > 0 && passcodeField.text.length !== 32; text: qsTr("%1/32").arg(passcodeField.text.length); color: Theme.warning }
                    }
                    PsSwitch { Layout.fillWidth: true; Layout.topMargin: 8; text: qsTr("Show the output when a task succeeds"); description: qsTr("Opens the file manager at the result."); checked: !!App.settings.openOutputAfterTask; onToggled: App.setSetting("openOutputAfterTask", checked) }
                }

                // ------------------------------------------------ File operations
                ColumnLayout {
                    visible: page.section === "files"
                    Layout.fillWidth: true
                    spacing: 14
                    PsSwitch { Layout.fillWidth: true; text: qsTr("Preview moves before they run"); description: qsTr("Shows where every item will go and what is skipped."); checked: App.settings.confirmMove !== false; onToggled: App.setSetting("confirmMove", checked) }
                    PsSwitch { Layout.fillWidth: true; text: qsTr("Confirm before moving to the trash"); checked: App.settings.confirmDelete !== false; onToggled: App.setSetting("confirmDelete", checked) }
                    PsSwitch { Layout.fillWidth: true; text: qsTr("Delete permanently instead of using the trash"); description: qsTr("Always asks first. Deleted items cannot be restored."); checked: !!App.settings.permanentDelete; onToggled: App.setSetting("permanentDelete", checked) }
                    Text { text: qsTr("Only items inside your library folders or items you opened can be deleted, and never while a task is using them."); color: Theme.textFaint; font.pixelSize: Theme.fontSmall + 1; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                }

                // ------------------------------------------------ Maintenance
                ColumnLayout {
                    visible: page.section === "maintenance"
                    Layout.fillWidth: true
                    spacing: 12
                    component MaintenanceRow: Card {
                        id: mrow
                        property string icon: ""
                        property string title: ""
                        property string text: ""
                        default property alias actions: mrowActions.data
                        Layout.fillWidth: true
                        implicitHeight: 84
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 18
                            spacing: 14
                            Icon { name: mrow.icon; size: 22 }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Text { text: mrow.title; color: Theme.text; font.weight: Font.DemiBold }
                                Text { text: mrow.text; color: Theme.textFaint; font.pixelSize: Theme.fontSmall; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }
                            Row { id: mrowActions; spacing: 8 }
                        }
                    }
                    MaintenanceRow {
                        icon: "export"; title: qsTr("Export preferences"); text: qsTr("Save your settings to a file. The passcode is left out unless you include it.")
                        PsCheckBox { id: includePasscode; text: qsTr("Include passcode") }
                        PsButton { compact: true; text: qsTr("Export…"); onClicked: App.saveFile(qsTr("Export preferences"), "PS5PKGTool-settings.json", ["JSON files (*.json)"], function (p) { App.call("settings.export", { path: p, includePasscode: includePasscode.checked }, function () { App.toast(qsTr("Preferences exported"), p, "success", "export") }) }) }
                    }
                    MaintenanceRow {
                        icon: "import"; title: qsTr("Import preferences"); text: qsTr("Load settings from a file. You'll see every change before it's applied. Works with files from the Windows edition.")
                        PsButton {
                            compact: true; text: qsTr("Import…")
                            onClicked: App.pickFile(qsTr("Import preferences"), ["JSON files (*.json)"], function (p) {
                                App.call("settings.importPreview", { path: p }, function (r) {
                                    if (r.changes.length === 0) { App.toast(qsTr("Nothing to change"), qsTr("The file matches your current preferences."), "info", "check"); return }
                                    App.confirm({ title: qsTr("Import these changes?"), items: r.changes, confirmLabel: qsTr("Import"), onAccept: function () { App.call("settings.importApply", { path: p }, function () { App.toast(qsTr("Preferences imported"), "", "success", "import"); App.scan() }) } })
                                })
                            })
                        }
                    }
                    MaintenanceRow {
                        icon: "refresh"; title: qsTr("Reset preferences"); text: qsTr("Back to defaults. Library folders, opened items, saved views and recent folders are kept.")
                        PsButton { compact: true; variant: "danger"; text: qsTr("Reset…"); onClicked: App.confirm({ title: qsTr("Reset all preferences?"), text: qsTr("Library folders, opened items and saved views are kept."), confirmLabel: qsTr("Reset"), danger: true, onAccept: function () { App.call("settings.reset") } }) }
                    }
                    MaintenanceRow {
                        icon: "broom"; title: qsTr("Clear caches"); text: page.cacheInfo ? qsTr("Decoded artwork and preview files (%1). They're rebuilt as needed.").arg(page.cacheInfo.artworkText) : qsTr("Decoded artwork and preview files.")
                        PsButton { compact: true; text: qsTr("Clear"); onClicked: App.call("app.clearCaches", {}, function () { App.call("app.cacheInfo", {}, function (r) { page.cacheInfo = r }); App.toast(qsTr("Caches cleared"), "", "success", "broom") }) }
                    }
                    MaintenanceRow {
                        icon: "terminal"; title: qsTr("Logs"); text: App.hello.logDirectory || ""
                        PsButton { compact: true; text: qsTr("Open folder"); onClicked: Desktop.openPath(App.hello.logDirectory) }
                    }
                    MaintenanceRow {
                        icon: "drive"; title: qsTr("Data folder"); text: App.hello.dataDirectory || ""
                        PsButton { compact: true; text: qsTr("Open folder"); onClicked: Desktop.openPath(App.hello.dataDirectory) }
                    }
                }

                // ------------------------------------------------ About
                ColumnLayout {
                    visible: page.section === "about"
                    Layout.fillWidth: true
                    spacing: 14
                    RowLayout {
                        spacing: 20
                        Image { source: "qrc:/qt/qml/PS5PkgTool/app/ps5pkgtool-256.png"; sourceSize: Qt.size(110, 110) }
                        ColumnLayout {
                            spacing: 4
                            Text { text: "PS5 PKG Tool"; color: Theme.text; font.pixelSize: Theme.fontTitle; font.weight: Font.DemiBold }
                            Text { text: qsTr("Linux edition %1").arg(Desktop.version); color: Theme.textDim }
                            Text { text: Desktop.platform; color: Theme.textFaint; font.pixelSize: Theme.fontSmall }
                            Text { text: App.hello.runtime ? qsTr("Engine %1 · %2").arg(App.hello.version).arg(App.hello.runtime) : ""; color: Theme.textFaint; font.pixelSize: Theme.fontSmall }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Theme.textDim
                        text: qsTr("Manage your PS5 dump and image collection, read PS5 packages, and build or convert images. This is not software for obtaining free PS5 games.\n\nExperimental: images and packages produced by this tool have been validated on PC but not on a jailbroken PS5. Keep backups and use generated output at your own risk.")
                    }
                    Card {
                        Layout.fillWidth: true
                        implicitHeight: backendColumn.implicitHeight + 28
                        ColumnLayout {
                            id: backendColumn
                            anchors.fill: parent
                            anchors.margins: 14
                            Text { text: qsTr("Package builders"); color: Theme.text; font.weight: Font.DemiBold }
                            Repeater {
                                model: App.hello.backends || []
                                delegate: RowLayout {
                                    required property var modelData
                                    Icon { name: modelData.available ? "check-circle" : "error"; color: modelData.available ? Theme.success : Theme.danger; size: 16 }
                                    Text { text: modelData.name + (modelData.available ? "" : " — " + modelData.reason); color: Theme.textDim; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                                }
                            }
                        }
                    }
                    FlowRow {
                        Layout.fillWidth: true
                        spacing: 10
                        PsButton { iconName: "link"; text: qsTr("Project on GitHub"); onClicked: Desktop.openUrl("https://github.com/pearlxcore/PS5PkgTool") }
                        PsButton { iconName: "warning"; text: qsTr("Report a problem"); onClicked: Desktop.openUrl("https://github.com/pearlxcore/PS5PkgTool/issues") }
                        PsButton { iconName: "heart"; text: qsTr("Support the author (Ko-fi)"); onClicked: Desktop.openUrl("https://ko-fi.com/R6R524N7X") }
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        wrapMode: Text.WordWrap
                        color: Theme.textFaint
                        font.pixelSize: Theme.fontSmall
                        text: qsTr("Licensed under GPL-3.0. Built with Qt 6 (LGPL-3.0) and .NET. Thanks to SvenGDK (LibProsperoPkg, UFS2Tool), PSBrew / Renan Barreto (MkPFS), kerrdec97, strongt1me and Robin Perris. See THIRD_PARTY_NOTICES.md.")
                    }
                    Text { text: qsTr("Keyboard: Ctrl+F search · F5 refresh · Ctrl+O open folder · Ctrl+Shift+O open file · Ctrl+1–4 pages · Ctrl+L log · arrows move · Enter details · Esc back · Menu key actions"); color: Theme.textFaint; font.pixelSize: Theme.fontSmall; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                }
            }
        }
    }
}
