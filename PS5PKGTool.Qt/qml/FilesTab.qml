import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import PS5PkgTool.Native

// Browse the files inside a dump, image or package, preview them (image, text, hex, media) and
// extract files or folders.
Item {
    id: root
    property string gameId: ""
    property var details: null
    property var preview: null
    property string previewError: ""
    property bool previewLoading: false
    property var hex: null
    property var selected: ({})

    FileBrowserModel { id: browser }

    Component.onCompleted: {
        App.call("files.list", { id: gameId }, function (result) {
            browser.setFiles(result.files)
            note.text = result.note
        })
    }

    function selectedPaths() {
        const paths = Object.keys(selected).filter(function (p) { return selected[p] })
        return paths
    }

    function openEntry(entry) {
        if (entry.isDir) {
            browser.folder = entry.path
            return
        }
        preview = null
        hex = null
        previewError = ""
        previewLoading = true
        const path = entry.path
        App.call("files.preview", { id: gameId, path: path }, function (result) {
            if (selected[path] === undefined && Object.keys(selected).length > 1) {}
            preview = result
            previewLoading = false
            if (result.kind === "hex") loadHex(0)
        }, function (e) { previewLoading = false; previewError = e.message })
    }

    function loadHex(offset) {
        App.call("files.hex", { id: gameId, path: preview.info.path, offset: offset }, function (result) { hex = result })
    }

    function extract(paths) {
        if (paths.length === 0) return
        App.pickFolder(qsTr("Extract to"), function (folder) {
            App.call("files.extract", { id: root.gameId, paths: paths, destination: folder })
        }, App.settings.outputDirectory)
    }

    RowLayout {
        anchors.fill: parent
        spacing: 16

        // Browser
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 3
            spacing: 10

            RowLayout {
                spacing: 8
                PsTextField {
                    icon: "search"
                    clearable: true
                    placeholderText: qsTr("Search all files")
                    Layout.preferredWidth: 280
                    onTextChanged: browser.search = text
                }
                Text {
                    text: qsTr("%1 files · %2").arg(browser.fileCount.toLocaleString(Qt.locale(), "f", 0)).arg(browser.formatBytes(browser.totalBytes))
                    color: Theme.textFaint
                    font.pixelSize: Theme.fontSmall + 1
                }
                Item { Layout.fillWidth: true }
                PsButton { compact: true; iconName: "extract"; text: root.selectedPaths().length > 0 ? qsTr("Extract %1").arg(root.selectedPaths().length) : qsTr("Extract folder"); onClicked: root.extract(root.selectedPaths().length > 0 ? root.selectedPaths().reduce(function (all, p) { return all.concat(browser.filesUnder(p).length > 0 ? browser.filesUnder(p) : [p]) }, []) : browser.filesUnder(browser.folder)) }
                PsButton { compact: true; iconName: "extract"; text: qsTr("Extract all"); onClicked: root.extract(browser.allFiles()) }
            }

            // Breadcrumbs
            Row {
                spacing: 4
                visible: browser.search.length === 0
                AbstractButton {
                    implicitHeight: 28
                    implicitWidth: rootLabel.implicitWidth + 16
                    onClicked: browser.folder = ""
                    contentItem: Text { id: rootLabel; text: qsTr("Root"); color: browser.folder.length === 0 ? Theme.text : Theme.accentBright; font.pixelSize: Theme.fontSmall + 1; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                    background: Rectangle { radius: 6; color: parent.hovered ? Theme.surfaceHover : "transparent" }
                }
                Repeater {
                    model: browser.crumbs
                    delegate: Row {
                        required property string modelData
                        required property int index
                        spacing: 4
                        Icon { name: "chevron-right"; size: 12; opacity: 0.5; anchors.verticalCenter: parent.verticalCenter }
                        AbstractButton {
                            implicitHeight: 28
                            implicitWidth: crumb.implicitWidth + 16
                            onClicked: browser.folder = browser.crumbs.slice(0, index + 1).join("/")
                            contentItem: Text { id: crumb; text: modelData; color: index === browser.crumbs.length - 1 ? Theme.text : Theme.accentBright; font.pixelSize: Theme.fontSmall + 1; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                            background: Rectangle { radius: 6; color: parent.hovered ? Theme.surfaceHover : "transparent" }
                        }
                    }
                }
            }

            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radius
                ListView {
                    id: fileList
                    anchors.fill: parent
                    anchors.margins: 6
                    clip: true
                    model: browser
                    focus: true
                    ScrollBar.vertical: ScrollBar {}
                    Keys.onReturnPressed: root.openEntry(browser.get(currentIndex))
                    Keys.onBackPressed: browser.up()
                    Keys.onPressed: (event) => { if (event.key === Qt.Key_Backspace) browser.up() }
                    delegate: Rectangle {
                        id: fileRow
                        required property int index
                        required property string name
                        required property string path
                        required property bool isDir
                        required property string sizeText
                        required property int items
                        required property string kind
                        required property bool encrypted
                        readonly property bool checked: !!root.selected[path]
                        width: ListView.view.width
                        height: 40
                        radius: 8
                        color: fileList.currentIndex === index ? Theme.accentSoft : hover.hovered ? Theme.surfaceHover : "transparent"
                        HoverHandler { id: hover }
                        TapHandler {
                            acceptedModifiers: Qt.KeyboardModifierMask
                            onTapped: (point) => {
                                fileList.currentIndex = fileRow.index
                                fileList.forceActiveFocus()
                                if (point.modifiers & Qt.ControlModifier) {
                                    const next = Object.assign({}, root.selected)
                                    next[fileRow.path] = !next[fileRow.path]
                                    root.selected = next
                                } else if (!fileRow.isDir) {
                                    root.openEntry(browser.get(fileRow.index))
                                }
                            }
                            onDoubleTapped: root.openEntry(browser.get(fileRow.index))
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10
                            PsCheckBox {
                                checked: fileRow.checked
                                onToggled: { const next = Object.assign({}, root.selected); next[fileRow.path] = checked; root.selected = next }
                            }
                            Icon { name: fileRow.isDir ? "folder" : fileRow.kind === "image" ? "image" : fileRow.kind === "text" ? "text" : fileRow.kind === "audio" ? "audio" : fileRow.kind === "video" ? "video" : fileRow.kind === "binary" ? "binary" : fileRow.kind === "archive" ? "archive" : "file"; size: 18; color: fileRow.isDir ? Theme.accentBright : "white" }
                            Text { text: fileRow.name; color: Theme.text; font.pixelSize: Theme.fontSmall + 1; elide: Text.ElideMiddle; Layout.fillWidth: true }
                            Icon { visible: fileRow.encrypted; name: "lock"; size: 14; color: Theme.warning }
                            Text { text: fileRow.isDir ? qsTr("%1 items").arg(fileRow.items) : ""; color: Theme.textFaint; font.pixelSize: Theme.fontSmall; Layout.preferredWidth: 80; horizontalAlignment: Text.AlignRight }
                            Text { text: fileRow.sizeText; color: Theme.textDim; font.pixelSize: Theme.fontSmall + 1; Layout.preferredWidth: 80; horizontalAlignment: Text.AlignRight }
                        }
                    }
                }
                Text { anchors.centerIn: parent; visible: browser.count === 0; text: browser.search.length > 0 ? qsTr("No files match.") : qsTr("No files."); color: Theme.textFaint }
            }
            Text { id: note; color: Theme.textFaint; font.pixelSize: Theme.fontSmall; Layout.fillWidth: true; elide: Text.ElideRight }
        }

        // Preview
        Card {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 2
            visible: App.settings.showFilePreview !== false
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                RowLayout {
                    visible: root.preview !== null
                    Layout.fillWidth: true
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text { text: root.preview ? root.preview.info.name : ""; color: Theme.text; font.pixelSize: Theme.fontBody; font.weight: Font.DemiBold; elide: Text.ElideMiddle; Layout.fillWidth: true }
                        Text {
                            text: root.preview ? [root.preview.info.format, root.preview.info.sizeText].concat(root.preview.info.metadata.map(function (m) { return m.name + " " + m.value })).join(" · ") : ""
                            color: Theme.textFaint; font.pixelSize: Theme.fontSmall; elide: Text.ElideRight; Layout.fillWidth: true
                        }
                    }
                    IconButton { iconName: "external"; size: 32; tip: qsTr("Open with the default app"); onClicked: App.call("files.materialize", { id: root.gameId, path: root.preview.info.path, size: root.preview.info.size }, function (r) { Desktop.openPath(r.file) }) }
                    IconButton { iconName: "extract"; size: 32; tip: qsTr("Extract…"); onClicked: root.extract([root.preview.info.path]) }
                    IconButton { iconName: "copy"; size: 32; tip: qsTr("Copy path"); onClicked: App.copy(root.preview.info.path) }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    EmptyState {
                        anchors.centerIn: parent
                        visible: root.preview === null && !root.previewLoading && root.previewError.length === 0
                        icon: "eye"
                        title: qsTr("Preview")
                        text: qsTr("Select a file to see it here: images, text and JSON, a hex view, or audio and video.")
                    }
                    PsProgressBar { anchors.centerIn: parent; width: 200; indeterminate: true; visible: root.previewLoading }
                    Text { anchors.centerIn: parent; width: parent.width - 40; visible: root.previewError.length > 0; text: root.previewError; color: Theme.danger; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter }

                    Image {
                        anchors.fill: parent
                        visible: root.preview !== null && root.preview.kind === "image"
                        source: visible ? Desktop.fileUrl(root.preview.file) : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        Rectangle { anchors.fill: parent; z: -1; color: Qt.rgba(0, 0, 0, 0.25); radius: 8 }
                    }

                    ScrollView {
                        anchors.fill: parent
                        visible: root.preview !== null && root.preview.kind === "text"
                        TextArea {
                            readOnly: true
                            selectByMouse: true
                            text: root.preview && root.preview.kind === "text" ? root.preview.text + (root.preview.truncated ? "\n\n… " + qsTr("preview truncated") + " …" : "") : ""
                            color: Theme.text
                            font.family: "monospace"
                            font.pixelSize: Theme.fontSmall
                            wrapMode: TextEdit.Wrap
                            background: null
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        visible: root.preview !== null && root.preview.kind === "hex"
                        spacing: 8
                        ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            TextArea {
                                readOnly: true
                                selectByMouse: true
                                text: root.hex ? root.hex.text : ""
                                color: Theme.textDim
                                font.family: "monospace"
                                font.pixelSize: Theme.fontSmall
                                wrapMode: TextEdit.NoWrap
                                background: null
                            }
                        }
                        RowLayout {
                            PsButton { compact: true; iconName: "back"; enabled: root.hex && root.hex.hasPrevious; onClicked: root.loadHex(Math.max(0, root.hex.offset - root.hex.length)) }
                            Text {
                                text: root.hex ? "0x" + root.hex.offset.toString(16).toUpperCase() + " – 0x" + (root.hex.offset + Math.max(0, root.hex.length - 1)).toString(16).toUpperCase() + "  /  " + Desktop.formatBytes(root.hex.fileSize) : ""
                                color: Theme.textFaint; font.pixelSize: Theme.fontSmall; font.family: "monospace"; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                            }
                            PsButton { compact: true; iconName: "chevron-right"; enabled: root.hex && root.hex.hasNext; onClicked: root.loadHex(root.hex.offset + root.hex.length) }
                        }
                    }

                    Loader {
                        id: mediaLoader
                        anchors.fill: parent
                        active: root.preview !== null && root.preview.kind === "media"
                        source: "MediaPreview.qml"
                        onLoaded: item.load(root.gameId, root.preview.info)
                        onStatusChanged: if (status === Loader.Error) mediaFallback.visible = true
                    }
                    EmptyState {
                        id: mediaFallback
                        anchors.centerIn: parent
                        visible: false
                        icon: "video"
                        title: qsTr("Media preview unavailable")
                        text: qsTr("Install the Qt Multimedia QML module to play audio and video here, or open the file with your default player.")
                    }
                }
            }
        }
    }
}
