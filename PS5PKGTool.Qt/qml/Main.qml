import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Effects
import QtQuick.Layouts
import PS5PkgTool.Native

ApplicationWindow {
    id: window

    required property var startup
    signal screenshotReady()

    // Shader effects (blur, masks, tints) need a GPU-backed scene graph.
    readonly property bool softwareRendering: backdrop.GraphicsInfo.api === GraphicsInfo.Software
    onSoftwareRenderingChanged: Theme.effects = !softwareRendering

    width: 1440
    height: 880
    minimumWidth: 1024
    minimumHeight: 640
    visible: true
    title: detailsView.visible && detailsView.row.title ? detailsView.row.title + " — PS5 PKG Tool" : "PS5 PKG Tool"
    color: Theme.background

    Component.onCompleted: {
        App.startup = startup
        if (startup.screenshot) screenshotTimer.start()
    }

    /// Called by a second launch (single instance) with the paths it was given.
    function openPaths(paths) {
        for (let i = 0; i < paths.length; ++i) if (paths[i]) App.openPath(paths[i])
    }

    // ------------------------------------------------------------------ background art

    Item {
        id: backdrop
        anchors.fill: parent
        readonly property string art: App.selectedRow.backgroundUrl || ""
        property bool flip: false

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.backgroundTop }
                GradientStop { position: 1; color: Theme.background }
            }
        }

        onArtChanged: {
            const target = flip ? artA : artB
            target.source = art
            flip = !flip
        }

        Repeater {
            model: 2
            delegate: Item {
                required property int index
                anchors.fill: parent
                visible: App.settings.backgroundArt !== false
                opacity: (index === 1) === backdrop.flip ? (App.settings.backgroundOpacity || 55) / 100 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.slow * 2; easing.type: Easing.InOutQuad } }
                Image {
                    id: layer
                    anchors.fill: parent
                    source: index === 0 ? artA.source : artB.source
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize: Theme.effects ? Qt.size(1280, 720) : Qt.size(160, 90)
                    smooth: true
                    visible: !Theme.effects
                }
                MultiEffect {
                    anchors.fill: parent
                    visible: Theme.effects
                    source: layer
                    blurEnabled: (App.settings.backgroundBlur || 0) > 0
                    blur: Math.min(1, (App.settings.backgroundBlur || 32) / 64)
                    blurMax: 64
                    saturation: -0.1
                }
            }
        }
        QtObject { id: artA; property string source: "" }
        QtObject { id: artB; property string source: "" }

        // Legibility scrims, as on the console: darker toward the bottom and the left.
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0.02, 0.03, 0.05, 0.35) }
                GradientStop { position: 0.45; color: Qt.rgba(0.02, 0.03, 0.05, 0.55) }
                GradientStop { position: 1.0; color: Qt.rgba(0.02, 0.03, 0.05, 0.96) }
            }
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.rgba(0.02, 0.03, 0.05, 0.75) }
                GradientStop { position: 0.6; color: Qt.rgba(0.02, 0.03, 0.05, 0.0) }
            }
        }
    }

    Connections {
        target: App
        function onSelectedIdChanged() { artTimer.restart() }
    }
    Timer {
        id: artTimer
        interval: 220
        onTriggered: if (App.selectedId.length > 0 && !App.selectedRow.backgroundUrl) Library.requestArt(App.selectedId, true)
    }

    // ------------------------------------------------------------------ chrome

    TopBar {
        id: topBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        detailsOpen: detailsView.visible
        onBackRequested: detailsView.close()
        z: 10
    }

    Rectangle {
        id: engineBanner
        visible: !Bridge.ready && Bridge.status.length > 0 && App.libraryLoaded
        anchors.top: topBar.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: bannerText.implicitWidth + 40
        height: 36
        radius: 18
        color: Theme.warning
        z: 11
        Text { id: bannerText; anchors.centerIn: parent; text: Bridge.status; color: "#1b1300"; font.weight: Font.DemiBold }
    }

    Item {
        id: pages
        anchors.top: topBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        PageHost { key: "games"; source: "GamesPage.qml"; visibleWhen: !detailsView.visible }
        PageHost { key: "tools"; source: "ToolsPage.qml" }
        PageHost { key: "tasks"; source: "TasksPage.qml" }
        PageHost { key: "settings"; source: "SettingsPage.qml" }

        DetailsPage {
            id: detailsView
            anchors.fill: parent
        }
    }

    Rectangle {
        id: splash
        anchors.fill: parent
        color: Theme.background
        visible: opacity > 0
        opacity: App.libraryLoaded ? 0 : 1
        z: 50
        Behavior on opacity { NumberAnimation { duration: Theme.slow } }
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 18
            Image { source: "qrc:/qt/qml/PS5PkgTool/app/ps5pkgtool-256.png"; sourceSize: Qt.size(112, 112); Layout.alignment: Qt.AlignHCenter }
            Text { text: "PS5 PKG Tool"; color: Theme.text; font.pixelSize: Theme.fontTitle; font.weight: Font.Light; Layout.alignment: Qt.AlignHCenter }
            PsProgressBar { indeterminate: true; Layout.preferredWidth: 220; Layout.alignment: Qt.AlignHCenter; visible: !Bridge.status.includes("could not") }
            Text {
                text: Bridge.status
                color: Theme.textDim
                font.pixelSize: Theme.fontSmall + 1
                Layout.maximumWidth: 520
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }

    ToastHost {
        id: toasts
        anchors.top: topBar.bottom
        anchors.right: parent.right
        anchors.topMargin: 6
        anchors.rightMargin: 24
        z: 100
    }

    // ------------------------------------------------------------------ dialogs and menus

    ConfirmDialog { id: confirmDialog }
    PlanDialog { id: planDialog }
    ReportDialog { id: reportDialog }
    PromptDialog { id: promptDialog }
    DuplicatesDialog { id: duplicatesDialog }
    GameMenu { id: gameMenu }
    LogDrawer { id: logDrawer }

    FolderDialog {
        id: folderDialog
        property var callback: null
        onAccepted: if (callback) callback(Desktop.localPath(selectedFolder))
    }
    FileDialog {
        id: fileDialog
        property var callback: null
        onAccepted: if (callback) callback(Desktop.localPath(selectedFile))
    }

    Connections {
        target: App
        function onToastRequested(toast) { toasts.show(toast) }
        function onLogRequested() { logDrawer.open() }
        function onConfirmRequested(options) { confirmDialog.ask(options) }
        function onPlanRequested(options) { planDialog.show(options) }
        function onReportRequested(title, text) { reportDialog.show(title, text) }
        function onPromptRequested(options) { promptDialog.ask(options) }
        function onDuplicatesRequested(result) { duplicatesDialog.show(result) }
        function onDetailsRequested(id) { detailsView.open(id) }
        function onMenuRequested(ids, anchor) { gameMenu.openFor(ids) }
        function onFolderRequested(options) {
            folderDialog.title = options.title
            folderDialog.callback = options.callback
            if (options.initial) folderDialog.currentFolder = Desktop.fileUrl(options.initial)
            folderDialog.open()
        }
        function onFileRequested(options) {
            fileDialog.title = options.title
            fileDialog.fileMode = FileDialog.OpenFile
            fileDialog.nameFilters = options.filters.length > 0 ? options.filters.concat(["All files (*)"]) : ["All files (*)"]
            fileDialog.callback = options.callback
            fileDialog.open()
        }
        function onSaveRequested(options) {
            fileDialog.title = options.title
            fileDialog.fileMode = FileDialog.SaveFile
            fileDialog.nameFilters = options.filters.length > 0 ? options.filters.concat(["All files (*)"]) : ["All files (*)"]
            fileDialog.selectedFile = Desktop.fileUrl(Desktop.joinPath(App.settings.outputDirectory || Desktop.homePath, options.name))
            fileDialog.callback = options.callback
            fileDialog.open()
        }
    }

    // Drop dumps, packages or images anywhere to open them; folders full of games become library folders.
    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]
        onEntered: (drag) => { drag.accept(Qt.CopyAction); dropHint.visible = true }
        onExited: dropHint.visible = false
        onDropped: (drop) => {
            dropHint.visible = false
            for (let i = 0; i < drop.urls.length; ++i) {
                const path = Desktop.localPath(drop.urls[i])
                if (!path) continue
                if (Desktop.isDir(path) && !Desktop.exists(path + "/sce_sys/param.json")) App.addFolder(path)
                else App.openPath(path)
            }
        }
    }
    Rectangle {
        id: dropHint
        visible: false
        anchors.fill: parent
        anchors.margins: 18
        radius: Theme.radiusLarge
        color: Qt.rgba(0, 0.44, 0.82, 0.18)
        border.width: 3
        border.color: Theme.accentBright
        z: 200
        EmptyState {
            anchors.centerIn: parent
            icon: "import"
            title: qsTr("Drop to open")
            text: qsTr("Dump folders, .pkg packages and exFAT, FFPKG or FFPFSC images open as single items. A folder of games becomes a library folder.")
        }
    }

    // ------------------------------------------------------------------ keyboard

    Shortcut { sequence: "Ctrl+F"; onActivated: { detailsView.close(); App.page = "games"; App.searchFocusRequested() } }
    Shortcut { sequences: ["F5", "Ctrl+R"]; onActivated: App.scan() }
    Shortcut { sequence: "Ctrl+O"; onActivated: App.pickFolder(qsTr("Open a dump folder"), function (path) { App.openPath(path) }) }
    Shortcut { sequence: "Ctrl+Shift+O"; onActivated: App.pickFile(qsTr("Open a package or image"), ["PS5 sources (*.pkg *.exfat *.ffpkg *.ffpfsc)"], function (path) { App.openPath(path) }) }
    Shortcut { sequence: "Ctrl+1"; onActivated: { detailsView.close(); App.page = "games" } }
    Shortcut { sequence: "Ctrl+2"; onActivated: App.page = "tools" }
    Shortcut { sequence: "Ctrl+3"; onActivated: App.page = "tasks" }
    Shortcut { sequences: ["Ctrl+,", "Ctrl+4"]; onActivated: App.page = "settings" }
    Shortcut { sequence: "Ctrl+L"; onActivated: logDrawer.open() }
    Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }
    Shortcut {
        sequences: ["Esc", "Back"]
        enabled: detailsView.visible
        onActivated: detailsView.close()
    }

    // ------------------------------------------------------------------ screenshots (--screenshot)

    Timer {
        id: screenshotTimer
        interval: 700
        repeat: true
        property int ticks: 0
        property bool prepared: false
        onTriggered: {
            ticks++
            if (!App.libraryLoaded || Library.totalCount === 0) return
            if (!prepared) {
                prepared = true
                ticks = 0
                switch (startup.page) {
                case "grid": App.setSetting("viewMode", "grid"); break
                case "list": App.setSetting("viewMode", "list"); App.groupBy = "family"; break
                case "details": App.openDetails(App.selectedId); break
                default:
                    if (startup.page.indexOf("details:") === 0) {
                        App.openDetails(App.selectedId)
                        detailsView.tab = startup.page.substring(8)
                    } else {
                        App.setSetting("viewMode", "rail")
                    }
                    break
                case "tools": App.openTools(App.selectedId, "convert", "pkg"); break
                case "tasks":
                    // Queue a few real jobs on the demo titles so the page shows live progress.
                    const ids = Library.visibleIds()
                    const jobs = [["ffpfsc", 0], ["exfat", 1], ["pkg", 3], ["ffpkg", 4]]
                    for (let j = 0; j < jobs.length && j < ids.length; ++j)
                        App.call("tools.enqueue", { source: ids[jobs[j][1]], action: "convert", target: jobs[j][0], overwrite: true,
                                                   output: startup.screenshot + "-" + j + "." + (jobs[j][0] === "pkg" ? "pkg" : jobs[j][0]),
                                                   options: { backend: "ppt", playGo: 1, compression: "Stored" } })
                    App.page = "tasks"
                    break
                case "settings": App.page = "settings"; break
                }
                return
            }
            if (ticks < 9) return
            stop()
            if (!Desktop.saveScreenshot(window, startup.screenshot)) console.warn("Screenshot failed:", startup.screenshot)
            window.screenshotReady()
        }
    }
}
