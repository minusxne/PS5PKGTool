import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import PS5PkgTool.Native

// The focused title: name, what it is, what you can do with it, and the facts that matter.
FocusScope {
    id: hero
    property var row: ({})
    property var summary: null
    readonly property bool hasRow: !!row && !!row.id
    readonly property bool canBuild: hasRow && (row.format === "Dump Files" || row.format === "exFAT" || row.format === "FFPKG" || row.format === "FFPFSC")
    readonly property bool isPackage: hasRow && row.format === "PKG"

    // Details (trophies, file counts) are loaded a moment after the selection settles.
    property var cache: ({})
    onRowChanged: {
        summary = hasRow && cache[row.id] ? cache[row.id] : null
        summaryTimer.restart()
    }
    Timer {
        id: summaryTimer
        interval: 650
        onTriggered: {
            if (!hero.hasRow || hero.row.missing || hero.cache[hero.row.id]) return
            const id = hero.row.id
            App.call("details.get", { id: id }, function (result) {
                const value = {
                    trophies: result.trophies,
                    files: result.files,
                    activities: result.activities && result.activities.present,
                    executable: result.executable
                }
                hero.cache[id] = value
                if (hero.row.id === id) hero.summary = value
            }, function () {})
        }
    }

    function trophyText() {
        if (!summary) return ""
        const t = summary.trophies
        if (!t || !t.present) return qsTr("None")
        return t.counts.total.toString()
    }
    function trophyDetail() {
        if (!summary || !summary.trophies || !summary.trophies.present) return summary ? qsTr("No trophy set") : qsTr("Loading…")
        const c = summary.trophies.counts
        const parts = []
        if (c.platinum) parts.push(c.platinum + " P")
        if (c.gold) parts.push(c.gold + " G")
        if (c.silver) parts.push(c.silver + " S")
        if (c.bronze) parts.push(c.bronze + " B")
        return parts.join(" · ")
    }
    function statusText() {
        if (!hasRow) return ""
        if (row.missing) return qsTr("Source missing")
        if (row.superseded) return qsTr("Older update")
        if (row.missingBase) return qsTr("No base game")
        if (row.warningCount > 0) return qsTr("Check metadata")
        return qsTr("Ready")
    }
    function statusDetail() {
        if (!hasRow) return ""
        if (row.missing) return qsTr("Not found on disk")
        if (row.superseded) return qsTr("A newer update is in the library")
        if (row.missingBase) return qsTr("Add the base game to install it")
        if (row.warningCount > 0) return qsTr("%1 metadata warning(s)").arg(row.warningCount)
        return row.format === "PKG" ? qsTr("Package") : qsTr("Readable")
    }

    Flickable {
        anchors.fill: parent
        contentHeight: column.implicitHeight + 20
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        visible: hero.hasRow

        ColumnLayout {
            id: column
            width: parent.width
            spacing: 14

            Text {
                Layout.fillWidth: true
                text: hero.row.title || ""
                color: Theme.text
                font.pixelSize: Theme.fontDisplay
                font.weight: Font.Light
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            FlowRow {
                Layout.fillWidth: true
                spacing: 8
                Badge { text: hero.row.role || ""; tint: Theme.roleColor(hero.row.role); visible: !!hero.row.role }
                Badge { text: hero.row.format || ""; icon: Theme.formatIcon(hero.row.format); tint: Theme.accentBright }
                Badge { text: hero.row.region || ""; icon: "globe"; tint: Theme.textDim; visible: !!hero.row.region && hero.row.region !== "Unknown" }
                Badge { text: hero.row.titleId || ""; tint: Theme.textDim; visible: !!hero.row.titleId }
                Badge { text: hero.row.platform || ""; tint: Theme.textDim; visible: !!hero.row.platform }
                Badge { text: qsTr("Missing"); tint: Theme.danger; icon: "error"; visible: !!hero.row.missing }
                Badge { text: qsTr("Superseded"); tint: Theme.warning; visible: !!hero.row.superseded }
                Badge { text: qsTr("Base game missing"); tint: Theme.warning; visible: !!hero.row.missingBase }
            }

            RowLayout {
                spacing: 10
                Layout.topMargin: 6
                PsButton {
                    id: detailsButton
                    variant: "primary"
                    iconName: "info"
                    text: qsTr("Details")
                    focus: true
                    enabled: !hero.row.missing
                    onClicked: App.openDetails(hero.row.id)
                    KeyNavigation.right: convertButton
                }
                PsButton {
                    id: convertButton
                    iconName: "convert"
                    text: qsTr("Convert")
                    enabled: !hero.row.missing && (hero.canBuild || hero.isPackage)
                    onClicked: App.openTools(hero.row.id, "convert", "")
                    KeyNavigation.right: buildButton
                }
                PsButton {
                    id: buildButton
                    iconName: "package"
                    text: qsTr("Build FPKG")
                    visible: hero.canBuild
                    enabled: !hero.row.missing
                    onClicked: App.openTools(hero.row.id, "convert", "pkg")
                    KeyNavigation.right: extractButton
                }
                PsButton {
                    id: extractButton
                    iconName: "extract"
                    text: qsTr("Extract")
                    visible: hero.isPackage || (hero.canBuild && hero.row.format !== "Dump Files")
                    enabled: !hero.row.missing
                    onClicked: App.openTools(hero.row.id, "extract", "")
                }
                PsButton {
                    iconName: "folder"
                    text: qsTr("Show")
                    onClicked: App.revealItem(hero.row.id)
                }
                IconButton {
                    iconName: "more"
                    tip: qsTr("More actions")
                    onClicked: App.menuRequested([hero.row.id], null)
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.topMargin: 2
                text: hero.row.location || ""
                color: Theme.textFaint
                font.pixelSize: Theme.fontSmall + 1
                elide: Text.ElideMiddle
            }

            FlowRow {
                Layout.fillWidth: true
                Layout.topMargin: 8
                spacing: 12
                InfoCard {
                    icon: "tag"
                    label: qsTr("Version")
                    value: hero.row.version || ""
                    detail: [hero.row.category, hero.row.masterVersion ? qsTr("master %1").arg(hero.row.masterVersion) : ""].filter(Boolean).join(" · ")
                }
                InfoCard {
                    icon: "drive"
                    label: qsTr("Size")
                    value: hero.row.sizeText || (hero.row.format === "Dump Files" ? qsTr("Measuring…") : "")
                    detail: hero.row.source || ""
                }
                InfoCard {
                    icon: "cpu"
                    label: qsTr("Requires")
                    value: hero.row.firmware ? qsTr("FW %1").arg(hero.row.firmware) : ""
                    detail: hero.row.sdk ? qsTr("SDK %1").arg(hero.row.sdk) : ""
                    accent: Theme.warning
                }
                InfoCard {
                    icon: "trophy"
                    label: qsTr("Trophies")
                    value: hero.trophyText()
                    detail: hero.trophyDetail()
                    accent: Theme.gold
                }
                InfoCard {
                    icon: "file"
                    label: qsTr("Files")
                    value: hero.summary && hero.summary.files ? hero.summary.files.count.toLocaleString(Qt.locale(), "f", 0) : ""
                    detail: hero.summary && hero.summary.files && hero.summary.files.largest.length > 0
                            ? qsTr("Largest: %1").arg(hero.summary.files.largest[0].sizeText) : hero.summary ? "" : qsTr("Loading…")
                }
                InfoCard {
                    icon: hero.row.missing ? "error" : hero.row.superseded || hero.row.missingBase ? "warning" : "check-circle"
                    label: qsTr("Status")
                    value: hero.statusText()
                    detail: hero.statusDetail()
                    accent: hero.row.missing ? Theme.danger : hero.row.superseded || hero.row.missingBase ? Theme.warning : Theme.success
                }
            }
        }
    }
}
