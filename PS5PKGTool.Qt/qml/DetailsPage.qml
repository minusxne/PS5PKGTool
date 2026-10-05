import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import QtQuick.Layouts
import PS5PkgTool.Native

// Everything about one title: overview, artwork, trophies, activities, files, executable,
// raw param.json and the package container.
FocusScope {
    id: page
    visible: false
    opacity: visible ? 1 : 0

    property string gameId: ""
    property var details: null
    property string error: ""
    property bool loading: false
    property string tab: "overview"
    readonly property var row: gameId.length > 0 && App.libraryRevision >= 0 ? Library.row(gameId) : ({})
    readonly property bool isPackage: row.format === "PKG"

    function open(id) {
        gameId = id
        tab = "overview"
        details = null
        error = ""
        visible = true
        forceActiveFocus()
        load()
    }
    function close() {
        visible = false
        details = null
    }
    function load() {
        loading = true
        const id = gameId
        App.call("details.get", { id: id }, function (result) {
            if (id !== page.gameId) return
            details = result
            loading = false
            if (result.artwork && result.artwork[0].path)
                Library.patchRow(id, { icon: result.artwork[0].path, background: result.artwork[2].path || result.artwork[1].path || "" })
        }, function (e) {
            if (id !== page.gameId) return
            loading = false
            error = e.message
        })
    }

    readonly property string keyArt: {
        if (!details || !details.artwork) return row.backgroundUrl || ""
        const pic = details.artwork[2].path || details.artwork[1].path
        return pic ? Desktop.fileUrl(pic) : (row.backgroundUrl || "")
    }

    // Header art (sharper than the home backdrop)
    Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 250
        clip: true
        Image {
            id: headerArt
            anchors.fill: parent
            source: page.keyArt
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize: Qt.size(1920, 1080)
            opacity: status === Image.Ready ? 0.7 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.slow } }
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(0.02, 0.03, 0.05, 0.1) }
                GradientStop { position: 1; color: Qt.rgba(0.02, 0.03, 0.05, 0.95) }
            }
        }

        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: Theme.padLarge
            anchors.rightMargin: Theme.padLarge
            anchors.bottomMargin: 16
            spacing: 22

            GameTile {
                tileSize: 128
                current: true
                gameId: page.gameId
                title: page.row.title || ""
                iconUrl: page.row.iconUrl || ""
                format: page.row.format || ""
                role: page.row.role || ""
                missing: !!page.row.missing
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: page.row.title || ""; color: Theme.text; font.pixelSize: Theme.fontTitle + 6; font.weight: Font.Light; Layout.fillWidth: true; elide: Text.ElideRight }
                FlowRow {
                    Layout.fillWidth: true
                    spacing: 8
                    Badge { text: page.row.role || ""; tint: Theme.roleColor(page.row.role); visible: !!page.row.role }
                    Badge { text: page.row.format || ""; icon: Theme.formatIcon(page.row.format); tint: Theme.accentBright }
                    Badge { text: page.row.titleId || ""; tint: Theme.textDim; visible: !!page.row.titleId }
                    Badge { text: page.row.version ? "v" + page.row.version : ""; tint: Theme.textDim; visible: !!page.row.version }
                    Badge { text: page.row.sizeText || ""; icon: "drive"; tint: Theme.textDim; visible: !!page.row.sizeText }
                    Badge { text: page.row.firmware ? "FW " + page.row.firmware : ""; icon: "cpu"; tint: Theme.warning; visible: !!page.row.firmware }
                }
            }
            RowLayout {
                spacing: 8
                Layout.alignment: Qt.AlignBottom
                PsButton { iconName: "convert"; text: qsTr("Convert"); onClicked: { page.close(); App.openTools(page.gameId, "convert", "") } }
                PsButton { iconName: "folder"; text: qsTr("Show"); onClicked: App.revealItem(page.gameId) }
                IconButton { iconName: "more"; tip: qsTr("More actions"); onClicked: App.menuRequested([page.gameId], null) }
            }
        }
    }

    TabStrip {
        id: tabs
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.leftMargin: Theme.padLarge
        current: page.tab
        tabs: [
            { key: "overview", label: qsTr("Overview") },
            { key: "artwork", label: qsTr("Artwork") },
            { key: "trophies", label: qsTr("Trophies") },
            { key: "activities", label: qsTr("Activities") },
            { key: "files", label: qsTr("Files") },
            { key: "executable", label: qsTr("Executable") },
            { key: "param", label: "param.json" },
            { key: "container", label: page.isPackage ? qsTr("Package") : qsTr("Container") }
        ]
        onSelected: (key) => page.tab = key
    }
    Rectangle { anchors.top: tabs.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.leftMargin: Theme.padLarge; anchors.rightMargin: Theme.padLarge; height: 1; color: Theme.outline }

    Item {
        id: content
        anchors.top: tabs.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: 16
        anchors.leftMargin: Theme.padLarge
        anchors.rightMargin: Theme.padLarge
        anchors.bottomMargin: 18

        ColumnLayout {
            anchors.centerIn: parent
            visible: page.loading
            spacing: 14
            PsProgressBar { indeterminate: true; Layout.preferredWidth: 240 }
            Text { text: qsTr("Reading %1…").arg(page.row.format === "PKG" ? qsTr("the package") : page.row.format === "Dump Files" ? qsTr("the dump") : qsTr("the image")); color: Theme.textDim; Layout.alignment: Qt.AlignHCenter }
        }
        EmptyState {
            anchors.centerIn: parent
            visible: page.error.length > 0
            icon: "error"
            title: qsTr("Could not read this item")
            text: page.error
            PsButton { text: qsTr("Try again"); onClicked: { page.error = ""; page.load() } }
        }

        Loader {
            anchors.fill: parent
            active: page.details !== null && page.visible
            sourceComponent: {
                switch (page.tab) {
                case "artwork": return artworkTab
                case "trophies": return trophiesTab
                case "activities": return activitiesTab
                case "files": return filesTab
                case "executable": return executableTab
                case "param": return paramTab
                case "container": return containerTab
                }
                return overviewTab
            }
        }
    }

    Component { id: overviewTab; OverviewTab { details: page.details } }
    Component { id: artworkTab; ArtworkTab { details: page.details } }
    Component { id: trophiesTab; TrophiesTab { details: page.details } }
    Component { id: activitiesTab; ActivitiesTab { details: page.details } }
    Component { id: filesTab; FilesTab { gameId: page.gameId; details: page.details } }
    Component { id: executableTab; ExecutableTab { gameId: page.gameId; details: page.details } }
    Component { id: paramTab; ParamTab { details: page.details } }
    Component { id: containerTab; ContainerTab { gameId: page.gameId } }

    Keys.onLeftPressed: switchTab(-1)
    Keys.onRightPressed: switchTab(1)
    function switchTab(step) {
        const keys = tabs.tabs.map(function (t) { return t.key })
        const index = (keys.indexOf(tab) + step + keys.length) % keys.length
        tab = keys[index]
    }
}
