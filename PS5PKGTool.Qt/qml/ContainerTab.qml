import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// Package/container structure: header, segments, CNT entries, param.sfo, keystone/NP, PlayGo, SI.
Item {
    id: root
    property string gameId: ""
    property var info: null
    property string error: ""
    property string section: "header"
    property string playgo: "chunks"

    Component.onCompleted: App.call("details.container", { id: gameId }, function (result) { info = result }, function (e) { error = e.message })

    PsProgressBar { anchors.centerIn: parent; width: 240; indeterminate: true; visible: root.info === null && root.error.length === 0 }
    EmptyState { anchors.centerIn: parent; visible: root.error.length > 0; icon: "error"; title: qsTr("Could not read the container"); text: root.error }

    ColumnLayout {
        anchors.fill: parent
        visible: root.info !== null
        spacing: 12

        TabStrip {
            current: root.section
            fontSize: Theme.fontBody
            tabs: root.info && root.info.isPackage
                  ? [{ key: "header", label: qsTr("Header") }, { key: "segments", label: qsTr("Segments") }, { key: "entries", label: qsTr("CNT entries") },
                     { key: "sfo", label: "param.sfo" }, { key: "keystone", label: qsTr("Keystone / NP") }, { key: "playgo", label: "PlayGo" }, { key: "si", label: qsTr("SI contents") }]
                  : [{ key: "header", label: qsTr("Source") }, { key: "sfo", label: "param.sfo" }, { key: "keystone", label: qsTr("Keystone / NP") }, { key: "playgo", label: "PlayGo" }]
            onSelected: (key) => root.section = key
        }

        Flickable {
            visible: root.section === "header"
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: headerList.implicitHeight
            clip: true
            PropertyList { id: headerList; width: Math.min(parent.width, 900); title: qsTr("Structure"); rows: root.info ? root.info.header : [] }
        }
        DataTable { visible: root.section === "segments"; Layout.fillWidth: true; Layout.fillHeight: true; table: root.info ? root.info.segments : ({}) }
        DataTable { visible: root.section === "entries"; Layout.fillWidth: true; Layout.fillHeight: true; table: root.info ? root.info.entries : ({}) }
        DataTable { visible: root.section === "sfo"; Layout.fillWidth: true; Layout.fillHeight: true; table: root.info ? root.info.sfo : ({}); emptyText: qsTr("No param.sfo in this source.") }
        DataTable { visible: root.section === "keystone"; Layout.fillWidth: true; Layout.fillHeight: true; table: root.info ? root.info.keystone : ({}); showSearch: false }
        DataTable { visible: root.section === "si"; Layout.fillWidth: true; Layout.fillHeight: true; table: root.info ? root.info.si : ({}) }

        ColumnLayout {
            visible: root.section === "playgo"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10
            Text { text: root.info ? root.info.playGo.summary : ""; color: Theme.textDim; font.pixelSize: Theme.fontSmall + 1; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            Row {
                spacing: 8
                Chip { text: qsTr("Chunks"); selected: root.playgo === "chunks"; onClicked: root.playgo = "chunks" }
                Chip { text: qsTr("Scenarios"); selected: root.playgo === "scenarios"; onClicked: root.playgo = "scenarios" }
                Chip { text: qsTr("Files"); selected: root.playgo === "files"; onClicked: root.playgo = "files" }
            }
            DataTable { Layout.fillWidth: true; Layout.fillHeight: true; table: root.info ? root.info.playGo[root.playgo] : ({}) }
        }
    }
}
