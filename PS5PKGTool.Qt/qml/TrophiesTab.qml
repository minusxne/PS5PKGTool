import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import PS5PkgTool.Native

// The trophy list as cards with icons and grade colours, filterable by grade, hidden and text.
Item {
    id: root
    property var details: null
    readonly property var set: details ? details.trophies : null
    property var grades: ({ Platinum: true, Gold: true, Silver: true, Bronze: true })
    property bool showHidden: true
    property string search: ""

    readonly property var visibleTrophies: {
        if (!set || !set.present) return []
        const needle = search.toLowerCase()
        return set.trophies.filter(function (t) {
            if (!grades[t.grade] && grades[t.grade] !== undefined) return false
            if (!showHidden && t.hidden) return false
            return needle.length === 0 || t.name.toLowerCase().indexOf(needle) >= 0 || t.description.toLowerCase().indexOf(needle) >= 0
        })
    }

    EmptyState {
        anchors.centerIn: parent
        visible: !root.set || !root.set.present
        icon: "trophy"
        title: qsTr("No trophies")
        text: root.set ? root.set.message : ""
    }

    ColumnLayout {
        anchors.fill: parent
        visible: !!root.set && root.set.present
        spacing: 14

        RowLayout {
            spacing: 14
            Repeater {
                model: [["Platinum", "platinum"], ["Gold", "gold"], ["Silver", "silver"], ["Bronze", "bronze"]]
                delegate: Rectangle {
                    id: gradeChip
                    required property var modelData
                    readonly property int count: root.set && root.set.present ? root.set.counts[modelData[1]] : 0
                    readonly property bool on: root.grades[modelData[0]]
                    implicitWidth: 120
                    implicitHeight: 64
                    radius: Theme.radius
                    color: on ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.03)
                    border.color: on ? Theme.gradeColor(modelData[0]) : Theme.outline
                    opacity: count === 0 ? 0.45 : 1
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 10
                        Icon { name: "trophy"; size: 26; color: Theme.gradeColor(gradeChip.modelData[0]) }
                        ColumnLayout {
                            spacing: 0
                            Text { text: gradeChip.count; color: Theme.text; font.pixelSize: Theme.fontHeading + 2; font.weight: Font.DemiBold }
                            Text { text: gradeChip.modelData[0]; color: Theme.textDim; font.pixelSize: Theme.fontSmall }
                        }
                    }
                    TapHandler {
                        onTapped: {
                            const next = Object.assign({}, root.grades)
                            next[gradeChip.modelData[0]] = !next[gradeChip.modelData[0]]
                            root.grades = next
                        }
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                spacing: 3
                Text { text: root.set ? root.set.title : ""; color: Theme.text; font.pixelSize: Theme.fontBody + 1; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                Text {
                    text: root.set ? [root.set.npCommunicationId, qsTr("version %1").arg(root.set.version), qsTr("language %1").arg(root.set.language),
                                      root.set.integrityValid ? qsTr("integrity OK") : qsTr("integrity check failed")].join(" · ") : ""
                    color: Theme.textDim; font.pixelSize: Theme.fontSmall + 1; elide: Text.ElideRight; Layout.fillWidth: true
                }
            }
        }

        RowLayout {
            spacing: 12
            PsTextField { icon: "search"; clearable: true; placeholderText: qsTr("Search trophies"); Layout.preferredWidth: 300; onTextChanged: root.search = text }
            PsCheckBox { text: qsTr("Show hidden"); checked: root.showHidden; onToggled: root.showHidden = checked }
            Text { text: qsTr("%1 of %2").arg(root.visibleTrophies.length).arg(root.set && root.set.present ? root.set.counts.total : 0); color: Theme.textFaint; font.pixelSize: Theme.fontSmall + 1 }
            Item { Layout.fillWidth: true }
            PsButton {
                compact: true; iconName: "export"; text: qsTr("Export CSV…")
                onClicked: App.saveFile(qsTr("Export trophies"), (root.details.row.titleId || "trophies") + "-trophies.csv", ["CSV files (*.csv)"], function (path) {
                    const quote = function (v) { v = String(v === undefined || v === null ? "" : v); return /[",\n]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v }
                    const lines = ["Id,Grade,Hidden,Name,Description,UnlockCondition"]
                    root.set.trophies.forEach(function (t) { lines.push([t.id, t.grade, t.hidden, t.name, t.description, t.unlockCondition].map(quote).join(",")) })
                    if (Desktop.writeText(path, lines.join("\n") + "\n")) App.toast(qsTr("Exported"), path, "success", "export")
                })
            }
            PsButton {
                compact: true; iconName: "image"; text: qsTr("Open icon folder")
                onClicked: {
                    const first = root.set.trophies.find(function (t) { return t.icon })
                    if (first) Desktop.openPath(Desktop.parentDir(first.icon))
                }
            }
        }

        GridView {
            id: trophyGrid
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            cellWidth: Math.floor(width / Math.max(1, Math.floor(width / 460)))
            cellHeight: 104
            model: root.visibleTrophies
            ScrollBar.vertical: ScrollBar {}
            delegate: Item {
                id: trophy
                required property var modelData
                width: trophyGrid.cellWidth
                height: trophyGrid.cellHeight
                Card {
                    anchors.fill: parent
                    anchors.margins: 6
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 14
                        Rectangle {
                            Layout.preferredWidth: 64
                            Layout.preferredHeight: 64
                            radius: 10
                            color: Qt.rgba(0, 0, 0, 0.3)
                            border.width: 2
                            border.color: Theme.gradeColor(trophy.modelData.grade)
                            clip: true
                            Image { anchors.fill: parent; anchors.margins: 2; source: trophy.modelData.icon ? Desktop.fileUrl(trophy.modelData.icon) : ""; asynchronous: true; fillMode: Image.PreserveAspectCrop; sourceSize: Qt.size(128, 128) }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            RowLayout {
                                Text { text: trophy.modelData.name || qsTr("(unnamed)"); color: Theme.text; font.pixelSize: Theme.fontBody; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                                Badge { visible: trophy.modelData.hidden; text: qsTr("Hidden"); tint: Theme.textDim; implicitHeight: 20 }
                            }
                            Text { text: trophy.modelData.description; color: Theme.textDim; font.pixelSize: Theme.fontSmall + 1; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight; Layout.fillWidth: true }
                            Text { text: trophy.modelData.grade + " · #" + trophy.modelData.id; color: Theme.gradeColor(trophy.modelData.grade); font.pixelSize: Theme.fontSmall }
                        }
                    }
                }
            }
        }
    }
}
