import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import PS5PkgTool.Native

// Tools: pick a source, pick what to do, adjust options (safe defaults, advanced on request),
// check the summary, add to the queue.
FocusScope {
    id: page

    property string source: ""
    property var info: null
    property string error: ""
    property string action: ""
    property string target: ""
    property var options: ({})
    property string output: ""
    property bool overwrite: false
    property bool advanced: false
    property var disk: null
    property bool editing: false
    property var perBuilder: ({})

    readonly property var row: source.length > 0 && App.libraryRevision >= 0 ? Library.row(source) : ({})
    readonly property var actionInfo: info ? info.actions.find(function (a) { return a.id === action }) : null
    readonly property var targetInfo: info ? info.targets.find(function (t) { return t.id === target }) : null
    readonly property bool needsOutput: action === "convert" || action === "extract"
    readonly property bool isPackageSource: info && info.kind === "package"

    function inspect(path) {
        source = path
        info = null
        error = ""
        editing = false
        if (!path) return
        App.call("tools.inspect", { source: path }, function (result) {
            info = result
            const wanted = App.toolsAction
            const usable = result.actions.filter(function (a) { return a.enabled })
            action = wanted && usable.some(function (a) { return a.id === wanted }) ? wanted : (usable.length > 0 ? usable[0].id : "")
            const wantedTarget = App.toolsTarget
            target = wantedTarget && result.targets.some(function (t) { return t.id === wantedTarget }) ? wantedTarget
                   : (result.targets.length > 0 ? result.targets[0].id : "")
            App.toolsAction = ""
            App.toolsTarget = ""
            resetOptions()
        }, function (e) { error = e.message })
    }

    function resetOptions() {
        const builders = App.buildOptions ? App.buildOptions.builders : []
        const backend = App.buildOptions ? App.buildOptions.defaultBackend : "ppt"
        const defaults = builders.find(function (b) { return b.id === backend }) || { defaults: {} }
        options = Object.assign({
            cluster: 0, ampr: true, block: 32768, fragment: 4096, density: 262144, minFree: 0, level: 7, gain: 1,
            passcode: info ? info.passcode : "", backend: backend, drm: "upgradable", packageType: "APP", sdk: -1,
            temp: App.buildOptions ? App.buildOptions.tempDirectory : ""
        }, defaults.defaults)
        perBuilder = {}
        suggestOutput()
    }

    function setOption(name, value) {
        const next = Object.assign({}, options)
        next[name] = value
        options = next
        if (name === "temp") diskTimer.restart()
    }

    function switchBuilder(id) {
        const remembered = Object.assign({}, perBuilder)
        remembered[options.backend] = { compression: options.compression, krakenLevel: options.krakenLevel, krakenThreads: options.krakenThreads,
                                        playGo: options.playGo, deterministic: options.deterministic, fakeSign: options.fakeSign, rightSprx: options.rightSprx }
        perBuilder = remembered
        const builder = App.buildOptions.builders.find(function (b) { return b.id === id })
        options = Object.assign({}, options, remembered[id] || builder.defaults, { backend: id })
    }

    function suggestOutput() {
        if (!info) { output = ""; return }
        output = action === "extract" ? info.extractOutput : targetInfo ? targetInfo.output : ""
        diskTimer.restart()
    }
    onActionChanged: suggestOutput()
    onTargetChanged: suggestOutput()
    onOutputChanged: diskTimer.restart()

    Timer {
        id: diskTimer
        interval: 300
        onTriggered: {
            page.disk = null
            if (!page.info || !page.needsOutput || page.output.length === 0) return
            App.call("tools.diskCheck", { source: page.source, output: page.output, temp: page.options.temp || "", target: page.action === "extract" ? "extract" : page.target },
                     function (result) { page.disk = result }, function () {})
        }
    }

    function run() {
        const send = function () {
            App.call("tools.enqueue", { source: source, action: action, target: target, output: output, overwrite: overwrite, options: options },
                     function (result) {
                         if (result.warning) App.toast(qsTr("Low disk space"), result.warning, "warning", "drive")
                         App.page = "tasks"
                     }, function (e) { App.showError(qsTr("Could not queue the job"), e) })
        }
        const danger = { repair: qsTr("Repair restores a damaged boot region when the other copy is valid, extracts every readable file, rebuilds the filesystem beside the original, verifies it, and only then replaces the original image."),
                         ampr: qsTr("This creates or refreshes the root ampr_emu.index. It can relocate the index, extend the root directory and grow the image; every change is rolled back if verification fails."),
                         rebuild: qsTr("This extracts every readable file, rebuilds all FFPKG metadata beside the original, verifies the replacement and only then swaps it in. It needs free space about the size of the image.") }
        if (danger[action]) App.confirm({ title: actionInfo.label + "?", text: danger[action], items: [source], confirmLabel: actionInfo.label, onAccept: send })
        else send()
    }

    Connections {
        target: App
        function onPageChanged() { if (App.page === "tools" && App.toolsSource.length > 0) { page.inspect(App.toolsSource); App.toolsSource = "" } }
    }
    Component.onCompleted: {
        if (App.toolsSource.length > 0) { inspect(App.toolsSource); App.toolsSource = "" }
        else if (App.selectedId.length > 0) inspect(App.selectedId)
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.padLarge
        anchors.rightMargin: Theme.padLarge
        anchors.bottomMargin: 20
        spacing: 24

        // ---------------------------------------------------------- source + actions
        ColumnLayout {
            Layout.preferredWidth: 400
            Layout.maximumWidth: 400
            Layout.fillHeight: true
            spacing: 14

            Text { text: qsTr("Source"); color: Theme.textDim; font.pixelSize: Theme.fontSmall; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.8 }

            Card {
                Layout.fillWidth: true
                implicitHeight: sourceColumn.implicitHeight + 32
                ColumnLayout {
                    id: sourceColumn
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12
                    RowLayout {
                        spacing: 14
                        GameTile {
                            tileSize: 84
                            current: true
                            gameId: page.row.id || ""
                            title: page.row.title || (page.info ? page.info.name : "")
                            iconUrl: page.row.iconUrl || ""
                            format: page.row.format || ""
                            visible: page.source.length > 0
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Text {
                                text: page.source.length === 0 ? qsTr("No source selected") : (page.info ? (page.info.title || page.info.name) : qsTr("Inspecting…"))
                                color: Theme.text; font.pixelSize: Theme.fontHeading; font.weight: Font.DemiBold
                                Layout.fillWidth: true; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.WordWrap
                            }
                            FlowRow {
                                Layout.fillWidth: true
                                spacing: 6
                                visible: page.info !== null
                                Badge { text: page.info ? page.info.kindLabel : ""; tint: Theme.accentBright }
                                Badge { text: page.info ? page.info.sizeText : ""; tint: Theme.textDim; visible: page.info && page.info.sizeBytes > 0 }
                                Badge { text: page.info ? page.info.titleId : ""; tint: Theme.textDim; visible: page.info && page.info.titleId.length > 0 }
                            }
                        }
                    }
                    Text {
                        visible: page.info !== null || page.error.length > 0
                        text: page.error.length > 0 ? page.error : page.info ? page.info.explanation : ""
                        color: page.error.length > 0 ? Theme.danger : Theme.textDim
                        font.pixelSize: Theme.fontSmall + 1
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    PsComboBox {
                        id: libraryPicker
                        Layout.fillWidth: true
                        model: Library.games
                        textRole: "title"
                        displayText: qsTr("Choose from the library…")
                        onActivated: (index) => page.inspect(Library.games.idAt(index))
                    }
                    RowLayout {
                        PsButton { compact: true; iconName: "folder"; text: qsTr("Dump folder…"); onClicked: App.pickFolder(qsTr("Choose a dump folder"), function (p) { page.inspect(p) }) }
                        PsButton { compact: true; iconName: "file"; text: qsTr("Package or image…"); onClicked: App.pickFile(qsTr("Choose a package or image"), ["PS5 sources (*.pkg *.exfat *.ffpkg *.ffpfsc)"], function (p) { page.inspect(p) }) }
                    }
                }
            }

            Text { text: qsTr("Action"); color: Theme.textDim; font.pixelSize: Theme.fontSmall; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.8; visible: page.info !== null; Layout.topMargin: 6 }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 6
                visible: page.info !== null
                model: page.info ? page.info.actions : []
                delegate: AbstractButton {
                    id: actionTile
                    required property var modelData
                    readonly property bool active: page.action === modelData.id
                    width: ListView.view.width
                    height: 64
                    enabled: modelData.enabled
                    hoverEnabled: true
                    onClicked: { page.action = modelData.id; page.editing = false }
                    ToolTip.visible: hovered && !enabled && modelData.reason.length > 0
                    ToolTip.text: modelData.reason
                    background: Rectangle {
                        radius: Theme.radius
                        color: actionTile.active ? "#ffffff" : actionTile.hovered ? Theme.surfaceHover : Qt.rgba(1, 1, 1, 0.04)
                        border.width: actionTile.visualFocus ? 2 : 0
                        border.color: Theme.accentBright
                        opacity: actionTile.enabled ? 1 : 0.45
                    }
                    contentItem: RowLayout {
                        spacing: 14
                        Item { implicitWidth: 4 }
                        Icon {
                            name: { const m = { convert: "convert", extract: "extract", verify: "verify", edit: "edit", repair: "repair", ampr: "layers", rebuild: "refresh" }; return m[actionTile.modelData.id] || "tools" }
                            size: 22
                            color: actionTile.active ? "#0b0e14" : "white"
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text { text: actionTile.modelData.label; color: actionTile.active ? "#0b0e14" : Theme.text; font.pixelSize: Theme.fontBody; font.weight: Font.DemiBold }
                            Text {
                                text: actionTile.enabled ? actionTile.modelData.description : actionTile.modelData.reason
                                color: actionTile.active ? Qt.rgba(0, 0, 0, 0.6) : Theme.textFaint
                                font.pixelSize: Theme.fontSmall
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }
            Item { Layout.fillHeight: true; visible: page.info === null }
        }

        // ---------------------------------------------------------- options + summary
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            EmptyState {
                anchors.centerIn: parent
                visible: page.source.length === 0
                icon: "tools"
                title: qsTr("Choose something to work on")
                text: qsTr("Pick an item from your library or browse to a dump folder, package or image. The tool shows what it can do with it.")
            }

            EditorView {
                anchors.fill: parent
                visible: page.editing
                source: page.editing ? page.source : ""
                onClosed: page.editing = false
            }

            Flickable {
                anchors.fill: parent
                visible: page.info !== null && !page.editing
                contentHeight: optionsColumn.implicitHeight + 30
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}

                ColumnLayout {
                    id: optionsColumn
                    width: parent.width - 14
                    spacing: 18

                    // Targets
                    ColumnLayout {
                        visible: page.action === "convert"
                        Layout.fillWidth: true
                        spacing: 10
                        Text { text: qsTr("Convert to"); color: Theme.textDim; font.pixelSize: Theme.fontSmall; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.8 }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: width > 900 ? 4 : 2
                            columnSpacing: 12
                            rowSpacing: 12
                            Repeater {
                                model: page.info ? page.info.targets : []
                                delegate: AbstractButton {
                                    id: targetTile
                                    required property var modelData
                                    readonly property bool active: page.target === modelData.id
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 128
                                    hoverEnabled: true
                                    onClicked: page.target = modelData.id
                                    background: Rectangle {
                                        radius: Theme.radiusLarge
                                        color: targetTile.active ? Theme.accentSoft : targetTile.hovered ? Theme.surfaceHover : Theme.surface
                                        border.width: targetTile.active ? 2 : 1
                                        border.color: targetTile.active ? Theme.accentBright : Theme.outline
                                        Behavior on color { ColorAnimation { duration: Theme.fast } }
                                    }
                                    contentItem: ColumnLayout {
                                        spacing: 6
                                        Icon { name: targetTile.modelData.id === "pkg" ? "package" : targetTile.modelData.id === "ffpfsc" ? "archive" : "drive"; size: 26; Layout.leftMargin: 6; Layout.topMargin: 4 }
                                        Text { text: targetTile.modelData.label; color: Theme.text; font.pixelSize: Theme.fontBody + 1; font.weight: Font.DemiBold; Layout.leftMargin: 6 }
                                        Text { text: targetTile.modelData.description; color: Theme.textDim; font.pixelSize: Theme.fontSmall; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.leftMargin: 6; Layout.rightMargin: 6; maximumLineCount: 3; elide: Text.ElideRight }
                                    }
                                }
                            }
                        }
                    }

                    // Per-target options
                    Card {
                        Layout.fillWidth: true
                        visible: (page.action === "convert" && page.target.length > 0) || page.action === "extract" || page.action === "verify" || page.action === "edit"
                        implicitHeight: settingsColumn.implicitHeight + 36

                        ColumnLayout {
                            id: settingsColumn
                            anchors.fill: parent
                            anchors.margins: 18
                            spacing: 14

                            Text {
                                text: page.action === "convert" ? qsTr("%1 options").arg(page.targetInfo ? page.targetInfo.label : "")
                                     : page.action === "edit" ? qsTr("Edit files") : page.actionInfo ? page.actionInfo.label : ""
                                color: Theme.text; font.pixelSize: Theme.fontHeading; font.weight: Font.DemiBold
                            }

                            // exFAT
                            GridLayout {
                                visible: page.action === "convert" && page.target === "exfat"
                                columns: 2; columnSpacing: 18; rowSpacing: 10
                                Text { text: qsTr("Cluster size"); color: Theme.textDim }
                                PsComboBox {
                                    model: [qsTr("Auto"), "32 KB", "64 KB"]
                                    currentIndex: page.options.cluster === 65536 ? 2 : page.options.cluster === 32768 ? 1 : 0
                                    onActivated: (i) => page.setOption("cluster", [0, 32768, 65536][i])
                                }
                                Text { text: qsTr("AMPR index"); color: Theme.textDim }
                                PsCheckBox { text: qsTr("Generate ampr_emu.index (recommended)"); checked: page.options.ampr !== false; onToggled: page.setOption("ampr", checked) }
                            }

                            // FFPKG
                            GridLayout {
                                visible: page.action === "convert" && page.target === "ffpkg"
                                columns: 2; columnSpacing: 18; rowSpacing: 10
                                Text { text: qsTr("Block size"); color: Theme.textDim }
                                PsComboBox { model: ["32 KB", "64 KB"]; currentIndex: page.options.block === 65536 ? 1 : 0; onActivated: (i) => page.setOption("block", [32768, 65536][i]) }
                                Text { text: qsTr("Fragment size"); color: Theme.textDim }
                                PsComboBox { model: ["4 KB", "64 KB"]; currentIndex: page.options.fragment === 65536 ? 1 : 0; onActivated: (i) => page.setOption("fragment", [4096, 65536][i]) }
                                Text { text: qsTr("Inode density"); color: Theme.textDim }
                                PsComboBox { model: [qsTr("256 KiB per inode"), qsTr("512 KiB per inode"), qsTr("1 MiB per inode")]; currentIndex: [262144, 524288, 1048576].indexOf(page.options.density); onActivated: (i) => page.setOption("density", [262144, 524288, 1048576][i]) }
                                Text { text: qsTr("Reserved free space"); color: Theme.textDim }
                                PsSpinBox { from: 0; to: 50; value: page.options.minFree || 0; textFromValue: function (v) { return v + " %" }; valueFromText: function (t) { return parseInt(t) }; onValueModified: page.setOption("minFree", value) }
                            }

                            // FFPFSC
                            GridLayout {
                                visible: page.action === "convert" && page.target === "ffpfsc"
                                columns: 2; columnSpacing: 18; rowSpacing: 10
                                Text { text: qsTr("Compression level"); color: Theme.textDim }
                                PsSpinBox { from: 1; to: 9; value: page.options.level || 7; onValueModified: page.setOption("level", value) }
                                Text { text: qsTr("Minimum gain"); color: Theme.textDim }
                                PsSpinBox { from: 0; to: 100; value: page.options.gain === undefined ? 1 : page.options.gain; textFromValue: function (v) { return v + " %" }; valueFromText: function (t) { return parseInt(t) }; onValueModified: page.setOption("gain", value) }
                                Item { implicitWidth: 1 }
                                Text { text: qsTr("Blocks that shrink by less than this stay uncompressed, which keeps loading fast."); color: Theme.textFaint; font.pixelSize: Theme.fontSmall; wrapMode: Text.WordWrap; Layout.maximumWidth: 420 }
                            }

                            // Debug package
                            ColumnLayout {
                                visible: page.action === "convert" && page.target === "pkg"
                                Layout.fillWidth: true
                                spacing: 12
                                RowLayout {
                                    visible: page.info && !page.info.canBuildPackage
                                    Icon { name: "warning"; color: Theme.warning; size: 18 }
                                    Text { text: page.info ? page.info.buildBlockedReason : ""; color: Theme.warning; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                }
                                GridLayout {
                                    columns: 2; columnSpacing: 18; rowSpacing: 10
                                    Text { text: qsTr("Content ID"); color: Theme.textDim }
                                    Text { text: page.info && page.info.contentId ? page.info.contentId : "—"; color: Theme.text; font.family: "monospace" }
                                    Text { text: qsTr("Passcode"); color: Theme.textDim }
                                    PsTextField { Layout.preferredWidth: 380; text: page.options.passcode || ""; font.family: "monospace"; maximumLength: 32; onTextEdited: page.setOption("passcode", text); placeholderText: qsTr("32 characters (blank = all zeros)") }
                                }
                                PsSwitch { text: qsTr("Advanced options"); description: qsTr("Builder, DRM, SDK, compression, PlayGo and workspace."); checked: page.advanced; onToggled: page.advanced = checked; Layout.fillWidth: true }
                                GridLayout {
                                    visible: page.advanced
                                    columns: 2; columnSpacing: 18; rowSpacing: 10
                                    Text { text: qsTr("Builder"); color: Theme.textDim }
                                    ColumnLayout {
                                        PsComboBox {
                                            Layout.preferredWidth: 320
                                            model: App.buildOptions ? App.buildOptions.builders.map(function (b) { return b.name + (b.available ? "" : qsTr(" (unavailable)")) }) : []
                                            currentIndex: App.buildOptions ? App.buildOptions.builders.findIndex(function (b) { return b.id === page.options.backend }) : 0
                                            onActivated: (i) => page.switchBuilder(App.buildOptions.builders[i].id)
                                        }
                                        Text {
                                            text: { if (!App.buildOptions) return ""; const b = App.buildOptions.builders.find(function (x) { return x.id === page.options.backend }); return b ? (b.available ? b.note : b.reason) : "" }
                                            color: Theme.textFaint; font.pixelSize: Theme.fontSmall; wrapMode: Text.WordWrap; Layout.maximumWidth: 420
                                        }
                                    }
                                    Text { text: qsTr("Package type"); color: Theme.textDim }
                                    PsComboBox { model: [qsTr("APP (application)"), qsTr("AC (additional content), not supported yet")]; currentIndex: page.options.packageType === "AC" ? 1 : 0; onActivated: (i) => page.setOption("packageType", i === 1 ? "AC" : "APP"); Layout.preferredWidth: 320 }
                                    Text { text: qsTr("DRM type"); color: Theme.textDim }
                                    PsComboBox { model: App.buildOptions ? App.buildOptions.drmModes.map(function (d) { return d.label }) : []; currentIndex: App.buildOptions ? App.buildOptions.drmModes.findIndex(function (d) { return d.id === page.options.drm }) : 0; onActivated: (i) => page.setOption("drm", App.buildOptions.drmModes[i].id) }
                                    Text { text: qsTr("SDK version"); color: Theme.textDim }
                                    PsComboBox { model: App.buildOptions ? [qsTr("Auto (from source)")].concat(App.buildOptions.sdkVersions.map(function (s) { return s.version })) : []; currentIndex: (page.options.sdk || -1) + 1; onActivated: (i) => page.setOption("sdk", i - 1) }
                                    Text { text: qsTr("Compression"); color: Theme.textDim }
                                    PsComboBox { model: App.buildOptions ? App.buildOptions.compressionModes.map(function (c) { return c.label }) : []; currentIndex: App.buildOptions ? App.buildOptions.compressionModes.findIndex(function (c) { return c.id === page.options.compression }) : 0; onActivated: (i) => page.setOption("compression", App.buildOptions.compressionModes[i].id); Layout.preferredWidth: 280 }
                                    Text { text: qsTr("Kraken level"); color: Theme.textDim }
                                    PsComboBox { model: App.buildOptions ? App.buildOptions.krakenLevels.map(function (k) { return k.name }) : []; currentIndex: App.buildOptions ? App.buildOptions.krakenLevels.findIndex(function (k) { return k.value === page.options.krakenLevel }) : 0; onActivated: (i) => page.setOption("krakenLevel", App.buildOptions.krakenLevels[i].value) }
                                    Text { text: qsTr("Kraken threads"); color: Theme.textDim }
                                    PsSpinBox { from: 0; to: 256; value: page.options.krakenThreads || 0; textFromValue: function (v) { return v === 0 ? qsTr("Auto") : v }; valueFromText: function (t) { return t === qsTr("Auto") ? 0 : parseInt(t) }; onValueModified: page.setOption("krakenThreads", value) }
                                    Text { text: qsTr("PlayGo chunks"); color: Theme.textDim }
                                    PsSpinBox { from: 1; to: 1000; value: page.options.playGo || 1; onValueModified: page.setOption("playGo", value) }
                                    Text { text: qsTr("Workspace"); color: Theme.textDim }
                                    RowLayout {
                                        PsTextField { Layout.preferredWidth: 320; text: page.options.temp || ""; onEditingFinished: page.setOption("temp", text) }
                                        PsButton { compact: true; iconName: "folder"; onClicked: App.pickFolder(qsTr("Workspace folder"), function (p) { page.setOption("temp", p) }) }
                                    }
                                    Item { implicitWidth: 1 }
                                    ColumnLayout {
                                        PsCheckBox { text: qsTr("Deterministic build (same input, same output)"); checked: !!page.options.deterministic; onToggled: page.setOption("deterministic", checked) }
                                        PsCheckBox { text: qsTr("Fake-sign modules"); enabled: page.options.backend !== "lpp"; checked: !!page.options.fakeSign; onToggled: page.setOption("fakeSign", checked) }
                                        PsCheckBox { text: qsTr("Inject debug right.sprx"); enabled: page.options.backend !== "lpp"; checked: !!page.options.rightSprx; onToggled: page.setOption("rightSprx", checked) }
                                    }
                                }
                            }

                            // Passcode for package extract / verify
                            GridLayout {
                                visible: page.isPackageSource && (page.action === "extract" || page.action === "verify")
                                columns: 2; columnSpacing: 18
                                Text { text: qsTr("Passcode"); color: Theme.textDim }
                                PsTextField { Layout.preferredWidth: 380; text: page.options.passcode || ""; font.family: "monospace"; maximumLength: 32; onTextEdited: page.setOption("passcode", text) }
                            }

                            Text {
                                visible: page.action === "verify"
                                text: page.isPackageSource ? qsTr("Reads the package with its passcode, checks the structure and the CNT metadata, and indexes every file.")
                                                           : qsTr("Reads the whole image back: filesystem structure, every directory and file, and (for FFPFSC) every compressed block.")
                                color: Theme.textDim; wrapMode: Text.WordWrap; Layout.fillWidth: true
                            }

                            ColumnLayout {
                                visible: page.action === "edit"
                                spacing: 10
                                Text { text: qsTr("Browse the image, queue replacements, additions and deletions, then apply them in one verified pass."); color: Theme.textDim; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                PsButton { variant: "accent"; iconName: "edit"; text: qsTr("Open the editor"); onClicked: page.editing = true }
                            }
                        }
                    }

                    // Danger actions explanation
                    Card {
                        Layout.fillWidth: true
                        visible: ["repair", "ampr", "rebuild"].indexOf(page.action) >= 0
                        implicitHeight: dangerText.implicitHeight + 40
                        border.color: Qt.rgba(1, 0.71, 0.29, 0.4)
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 20
                            spacing: 14
                            Icon { name: "warning"; color: Theme.warning; size: 24; Layout.alignment: Qt.AlignTop }
                            Text {
                                id: dangerText
                                text: page.action === "repair" ? qsTr("Repair modifies the image in place. It first rebuilds a verified copy beside the original and only replaces the original once that copy checks out. Make sure there is free space about the size of the image.")
                                     : page.action === "ampr" ? qsTr("Refreshing the AMPR index changes the image in place. All changes are rolled back if the result does not verify.")
                                     : qsTr("Rebuild writes a verified replacement beside the original and swaps it in at the end. It needs free space about the size of the image.")
                                color: Theme.textDim; wrapMode: Text.WordWrap; Layout.fillWidth: true
                            }
                        }
                    }

                    // Output + summary
                    Card {
                        Layout.fillWidth: true
                        visible: page.needsOutput && (page.action !== "convert" || page.target.length > 0)
                        implicitHeight: outputColumn.implicitHeight + 36
                        ColumnLayout {
                            id: outputColumn
                            anchors.fill: parent
                            anchors.margins: 18
                            spacing: 12
                            Text { text: qsTr("Output"); color: Theme.text; font.pixelSize: Theme.fontHeading; font.weight: Font.DemiBold }
                            RowLayout {
                                Layout.fillWidth: true
                                PsTextField { Layout.fillWidth: true; text: page.output; onEditingFinished: page.output = text; font.family: "monospace" }
                                PsButton {
                                    compact: true
                                    iconName: "folder"
                                    text: qsTr("Browse…")
                                    onClicked: page.action === "extract"
                                               ? App.pickFolder(qsTr("Extract into"), function (p) { page.output = p })
                                               : App.saveFile(qsTr("Save as"), Desktop.fileName(page.output), [page.targetInfo.label + " (*" + page.targetInfo.extension + ")"], function (p) { page.output = p })
                                }
                            }
                            PsCheckBox { visible: page.action === "convert"; text: qsTr("Overwrite if the file exists"); checked: page.overwrite; onToggled: page.overwrite = checked }
                            RowLayout {
                                visible: page.disk !== null && page.disk.message.length > 0
                                spacing: 10
                                Icon {
                                    name: page.disk && page.disk.status === "Ok" ? "check-circle" : "warning"
                                    color: page.disk && page.disk.status === "Insufficient" ? Theme.danger : page.disk && page.disk.status === "NearLimit" ? Theme.warning : Theme.success
                                    size: 18
                                }
                                Text {
                                    text: page.disk ? (page.disk.status === "Insufficient" ? qsTr("Not enough free space: ") : page.disk.status === "NearLimit" ? qsTr("Low on space: ") : qsTr("Enough free space: ")) + page.disk.message : ""
                                    color: Theme.textDim; font.pixelSize: Theme.fontSmall + 1; wrapMode: Text.WordWrap; Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    // Go
                    RowLayout {
                        Layout.fillWidth: true
                        visible: page.action.length > 0 && page.action !== "edit"
                        Text {
                            Layout.fillWidth: true
                            text: page.action === "convert" && page.targetInfo
                                  ? qsTr("%1  →  %2").arg(page.info.kindLabel).arg(page.targetInfo.label)
                                  : page.actionInfo ? page.actionInfo.label + " · " + (page.info ? page.info.name : "") : ""
                            color: Theme.textDim
                            font.pixelSize: Theme.fontBody
                            elide: Text.ElideMiddle
                        }
                        PsButton {
                            variant: "primary"
                            iconName: "add"
                            text: qsTr("Add to queue")
                            enabled: page.info !== null && (!page.needsOutput || page.output.length > 0)
                                     && !(page.target === "pkg" && page.action === "convert" && (!page.info.canBuildPackage || page.options.packageType === "AC"))
                                     && !(page.disk && page.disk.status === "Insufficient" && page.target !== "pkg")
                            onClicked: page.run()
                        }
                    }
                }
            }
        }
    }
}
