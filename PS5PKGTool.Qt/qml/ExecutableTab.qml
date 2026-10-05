import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import PS5PkgTool.Native

// eboot.bin: SELF/ELF header facts, modules, program and section headers, SELF segments.
Item {
    id: root
    property string gameId: ""
    property var details: null
    readonly property var exe: details ? details.executable : null
    property string section: "modules"
    property string sha: ""

    EmptyState {
        anchors.centerIn: parent
        visible: !root.exe || !root.exe.present
        icon: "binary"
        title: qsTr("No executable")
        text: root.exe ? root.exe.message : ""
    }

    RowLayout {
        anchors.fill: parent
        visible: !!root.exe && root.exe.present
        spacing: 16

        ColumnLayout {
            Layout.preferredWidth: 380
            Layout.fillHeight: true
            spacing: 12
            PropertyList {
                Layout.fillWidth: true
                title: "eboot.bin"
                rows: root.exe && root.exe.present ? root.exe.header : []
            }
            Card {
                Layout.fillWidth: true
                implicitHeight: hashColumn.implicitHeight + 28
                ColumnLayout {
                    id: hashColumn
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 8
                    Text { text: "SHA-256"; color: Theme.textDim; font.pixelSize: Theme.fontSmall; font.weight: Font.DemiBold }
                    Text {
                        text: root.sha.length > 0 ? root.sha : qsTr("Not computed yet")
                        color: root.sha.length > 0 ? Theme.text : Theme.textFaint
                        font.family: "monospace"; font.pixelSize: Theme.fontSmall
                        wrapMode: Text.WrapAnywhere; Layout.fillWidth: true
                    }
                    RowLayout {
                        PsButton {
                            id: hashButton
                            compact: true; iconName: "verify"; text: qsTr("Compute")
                            onClicked: {
                                enabled = false
                                App.call("details.ebootHash", { id: root.gameId }, function (r) { root.sha = r.sha256; hashButton.enabled = true },
                                         function (e) { hashButton.enabled = true; App.showError(qsTr("Hash failed"), e) })
                            }
                        }
                        PsButton { compact: true; iconName: "copy"; text: qsTr("Copy"); visible: root.sha.length > 0; onClicked: App.copy(root.sha, "SHA-256") }
                    }
                }
            }
            PsButton {
                iconName: "extract"
                text: qsTr("Extract eboot and modules…")
                onClicked: App.pickFolder(qsTr("Extract executables to"), function (folder) {
                    App.call("files.extract", { id: root.gameId, paths: ["eboot.bin"].concat(root.exe.modulePaths), destination: folder })
                }, App.settings.outputDirectory)
            }
            Item { Layout.fillHeight: true }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10
            Text { text: root.exe && root.exe.present ? root.exe.summary : ""; color: Theme.textDim; font.pixelSize: Theme.fontSmall + 1; Layout.fillWidth: true; elide: Text.ElideRight }
            TabStrip {
                current: root.section
                fontSize: Theme.fontBody
                tabs: [
                    { key: "modules", label: qsTr("Modules") },
                    { key: "programs", label: qsTr("Program headers") },
                    { key: "sections", label: qsTr("Sections") },
                    { key: "segments", label: qsTr("SELF segments") }
                ]
                onSelected: (key) => root.section = key
            }
            DataTable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                table: root.exe && root.exe.present ? root.exe[root.section] : ({})
            }
        }
    }
}
