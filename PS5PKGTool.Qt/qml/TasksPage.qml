import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import PS5PkgTool.Native

// The queue, styled after the console's downloads list: one card per job with its art, route,
// two progress bars, timing and actions.
FocusScope {
    id: page
    property string filter: "all"
    property string search: ""

    readonly property var shown: App.tasks.filter(function (task) {
        if (search.length > 0 && task.title.toLowerCase().indexOf(search.toLowerCase()) < 0 && task.sourcePath.toLowerCase().indexOf(search.toLowerCase()) < 0) return false
        switch (filter) {
        case "active": return task.status === "Running" || task.status === "Queued" || task.status === "Cancelling"
        case "attention": return task.status === "Failed" || task.status === "Interrupted" || task.status === "Cancelled"
        case "finished": return task.status === "Completed"
        }
        return true
    }).slice().sort(function (a, b) {
        const order = { Running: 0, Cancelling: 1, Queued: 2, Failed: 3, Interrupted: 4, Cancelled: 5, Completed: 6 }
        const byStatus = (order[a.status] || 9) - (order[b.status] || 9)
        if (byStatus !== 0) return byStatus
        if (a.status === "Queued") return a.queuePosition - b.queuePosition
        return (b.completedUtc || b.createdUtc).localeCompare(a.completedUtc || a.createdUtc)
    })

    Component.onCompleted: App.unseenFinished = 0

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.padLarge
        anchors.rightMargin: Theme.padLarge
        anchors.bottomMargin: 18
        spacing: 14

        RowLayout {
            spacing: 10
            Text {
                text: App.taskSummary.total === 0 ? qsTr("No tasks yet")
                      : qsTr("%1 running · %2 waiting · %3 need attention · %4 done").arg(App.taskSummary.running).arg(App.taskSummary.waiting)
                            .arg(App.taskSummary.attention).arg(App.taskSummary.finished)
                color: Theme.textDim
                font.pixelSize: Theme.fontBody
            }
            Item { Layout.fillWidth: true }
            PsTextField { icon: "search"; clearable: true; placeholderText: qsTr("Find a task"); Layout.preferredWidth: 220; onTextChanged: page.search = text }
            Repeater {
                model: [["all", qsTr("All")], ["active", qsTr("Active")], ["attention", qsTr("Needs attention")], ["finished", qsTr("Finished")]]
                delegate: Chip { required property var modelData; text: modelData[1]; selected: page.filter === modelData[0]; onClicked: page.filter = modelData[0] }
            }
        }

        RowLayout {
            spacing: 10
            PsSwitch {
                text: qsTr("Run the queue")
                description: App.taskSummary.autoStart ? qsTr("Jobs start one after another automatically.") : qsTr("Held: only “Start next” runs a job.")
                checked: App.taskSummary.autoStart
                onToggled: App.call("tasks.setAutoStart", { value: checked })
                Layout.preferredWidth: 360
            }
            PsButton { compact: true; iconName: "play"; text: qsTr("Start next"); enabled: App.taskSummary.waiting > 0; onClicked: App.call("tasks.startNext") }
            PsButton { compact: true; iconName: "stop"; text: qsTr("Cancel all"); enabled: App.taskSummary.running + App.taskSummary.waiting > 0; onClicked: App.confirm({ title: qsTr("Cancel every running and waiting task?"), confirmLabel: qsTr("Cancel all"), cancelLabel: qsTr("Keep"), danger: true, onAccept: function () { App.call("tasks.cancelAll") } }) }
            PsButton { compact: true; iconName: "broom"; text: qsTr("Clear finished"); enabled: App.taskSummary.finished > 0; onClicked: App.call("tasks.clearCompleted") }
            Item { Layout.fillWidth: true }
            PsButton { compact: true; iconName: "terminal"; text: qsTr("Log"); onClicked: App.logRequested() }
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 12
            model: page.shown
            ScrollBar.vertical: ScrollBar {}
            add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.normal } }
            displaced: Transition { NumberAnimation { properties: "y"; duration: Theme.normal; easing.type: Easing.OutCubic } }
            delegate: TaskCard { required property var modelData; task: modelData; width: ListView.view.width }

            EmptyState {
                anchors.centerIn: parent
                visible: page.shown.length === 0
                icon: "tasks"
                title: App.tasks.length === 0 ? qsTr("Nothing in the queue") : qsTr("No tasks match")
                text: App.tasks.length === 0 ? qsTr("Conversions, extractions, package builds and other long jobs run here one at a time. They are saved between launches.") : ""
                PsButton { visible: App.tasks.length === 0; variant: "primary"; iconName: "tools"; text: qsTr("Open Tools"); onClicked: App.page = "tools" }
            }
        }
    }
}
