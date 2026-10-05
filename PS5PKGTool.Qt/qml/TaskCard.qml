import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import PS5PkgTool.Native

// One queued job: art, route, step and overall progress, timing, result and actions.
Card {
    id: card
    property var task: ({})
    readonly property var row: Library.contains(task.sourcePath) ? Library.row(task.sourcePath) : ({})
    readonly property bool running: task.status === "Running" || task.status === "Cancelling"
    readonly property color tint: Theme.statusColor(task.status)

    implicitHeight: content.implicitHeight + 32
    border.color: running ? Qt.rgba(0.18, 0.55, 1, 0.5) : Theme.outline

    RowLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        spacing: 18

        Rectangle {
            Layout.preferredWidth: 88
            Layout.preferredHeight: 88
            Layout.alignment: Qt.AlignTop
            radius: Theme.radius
            color: Theme.surfaceRaised
            clip: true
            Image { anchors.fill: parent; source: card.row.iconUrl || ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(176, 176) }
            Icon {
                anchors.centerIn: parent
                visible: !card.row.iconUrl
                name: { const t = card.task.type || ""; return t.indexOf("Extract") >= 0 ? "extract" : t.indexOf("Verify") >= 0 ? "verify" : t === "Build package" ? "package" : t === "Move" ? "move" : t.indexOf("Edit") >= 0 ? "edit" : "convert" }
                size: 34
                opacity: 0.6
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            RowLayout {
                spacing: 10
                Text { text: card.task.title || ""; color: Theme.text; font.pixelSize: Theme.fontBody + 2; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                Badge { text: card.task.status === "Queued" && card.task.queuePosition > 0 ? qsTr("Queued #%1").arg(card.task.queuePosition) : card.task.status; tint: card.tint }
            }
            RowLayout {
                spacing: 8
                Text { text: card.task.operation || ""; color: Theme.textDim; font.pixelSize: Theme.fontSmall + 1 }
                Text { visible: !!card.task.route; text: "·  " + card.task.route; color: Theme.textDim; font.pixelSize: Theme.fontSmall + 1; elide: Text.ElideRight; Layout.fillWidth: true }
                Item { Layout.fillWidth: !card.task.route }
                Text { text: [card.task.elapsed, card.task.eta].filter(function (s) { return s && s.length > 0 }).join("  ·  "); color: Theme.textFaint; font.pixelSize: Theme.fontSmall + 1 }
            }

            ColumnLayout {
                visible: card.running || card.task.status === "Queued"
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 4
                RowLayout {
                    Text { text: card.task.stepText ? card.task.stepText + ": " + card.task.stage : (card.task.stage || qsTr("Waiting")); color: Theme.textDim; font.pixelSize: Theme.fontSmall; elide: Text.ElideRight; Layout.fillWidth: true }
                    Text { text: Math.round((card.task.taskPercent || 0) * 100) + "%"; color: Theme.text; font.pixelSize: Theme.fontSmall + 1; font.weight: Font.DemiBold }
                }
                PsProgressBar { Layout.fillWidth: true; value: card.task.stepPercent || 0; indeterminate: card.running && (card.task.stepPercent || 0) <= 0; implicitHeight: 4; color: Qt.rgba(1, 1, 1, 0.7) }
                PsProgressBar { Layout.fillWidth: true; value: card.task.taskPercent || 0; implicitHeight: 8 }
                Text { visible: !!card.task.counts || !!card.task.currentFile; text: [card.task.counts, card.task.currentFile].filter(Boolean).join("   "); color: Theme.textFaint; font.pixelSize: Theme.fontSmall; elide: Text.ElideMiddle; Layout.fillWidth: true }
            }

            Text {
                visible: !card.running && card.task.status !== "Queued"
                text: card.task.result || ""
                color: card.task.status === "Failed" || card.task.status === "Interrupted" ? Theme.danger : card.task.status === "Completed" ? Theme.textDim : Theme.warning
                font.pixelSize: Theme.fontSmall + 1
                wrapMode: Text.WrapAnywhere
                maximumLineCount: 3
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            RowLayout {
                spacing: 8
                Layout.topMargin: 4
                PsButton { compact: true; iconName: "folder"; text: qsTr("Show output"); visible: card.task.outputExists; onClicked: Desktop.reveal(card.task.outputPath) }
                PsButton { compact: true; iconName: "stop"; text: qsTr("Cancel"); visible: card.task.canCancel; onClicked: App.call("tasks.cancel", { id: card.task.id }) }
                PsButton { compact: true; iconName: "refresh"; text: qsTr("Retry"); visible: card.task.canRetry; onClicked: App.call("tasks.retry", { id: card.task.id }) }
                PsButton {
                    compact: true; iconName: "add"; text: qsTr("Open result")
                    visible: card.task.status === "Completed" && card.task.outputExists && /\.(pkg|exfat|ffpkg|ffpfsc)$/i.test(card.task.outputPath)
                    onClicked: App.openPath(card.task.outputPath)
                }
                Item { Layout.fillWidth: true }
                IconButton { iconName: "info"; size: 32; tip: qsTr("Diagnostic report"); onClicked: App.call("tasks.report", { id: card.task.id }, function (r) { App.reportRequested(card.task.title, r.report) }) }
                IconButton { iconName: "trash"; size: 32; tip: qsTr("Remove from the list"); visible: card.task.canRemove; onClicked: App.call("tasks.remove", { id: card.task.id }) }
            }
        }
    }
}
