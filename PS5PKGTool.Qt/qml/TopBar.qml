import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import PS5PkgTool.Native

// The console-style top bar: large text tabs on the left, status icons and a clock on the right.
Item {
    id: bar
    property bool detailsOpen: false
    signal backRequested()
    implicitHeight: 76

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.padLarge
        anchors.rightMargin: Theme.padLarge - 8
        spacing: 18

        IconButton {
            visible: bar.detailsOpen
            iconName: "back"
            tip: qsTr("Back (Esc)")
            onClicked: bar.backRequested()
        }

        TabStrip {
            Layout.alignment: Qt.AlignVCenter
            fontSize: 21
            spacing: 34
            current: App.page
            tabs: [
                { key: "games", label: qsTr("Games") },
                { key: "tools", label: qsTr("Tools") },
                { key: "tasks", label: qsTr("Tasks") }
            ]
            onSelected: (key) => {
                if (bar.detailsOpen) bar.backRequested()
                App.page = key
                if (key === "tasks") App.unseenFinished = 0
            }
        }

        Item { Layout.fillWidth: true }

        // Scan progress
        RowLayout {
            visible: App.scanning
            spacing: 10
            PsProgressBar {
                Layout.preferredWidth: 140
                indeterminate: App.scanTotal === 0
                value: App.scanTotal > 0 ? App.scanProcessed / App.scanTotal : 0
            }
            Text {
                text: App.scanTotal > 0 ? qsTr("Scanning %1/%2").arg(App.scanProcessed).arg(App.scanTotal) : qsTr("Scanning…")
                color: Theme.textDim
                font.pixelSize: Theme.fontSmall + 1
            }
            IconButton { iconName: "close"; size: 30; tip: qsTr("Stop scanning"); onClicked: App.call("library.cancelScan") }
        }

        IconButton {
            iconName: "search"
            tip: qsTr("Search the library (Ctrl+F)")
            onClicked: { if (bar.detailsOpen) bar.backRequested(); App.page = "games"; App.searchFocusRequested() }
        }

        // Task activity: a ring for the running task, a dot for unseen results.
        Item {
            implicitWidth: 40
            implicitHeight: 40
            RingProgress {
                anchors.fill: parent
                anchors.margins: 3
                visible: App.taskSummary.running > 0
                value: App.taskSummary.activePercent || 0
            }
            IconButton {
                anchors.centerIn: parent
                iconName: "tasks"
                size: 36
                tip: App.taskSummary.running > 0
                     ? qsTr("%1 · %2%").arg(App.taskSummary.activeTitle).arg(Math.round((App.taskSummary.activePercent || 0) * 100))
                     : App.taskSummary.waiting > 0 ? qsTr("%1 waiting").arg(App.taskSummary.waiting) : qsTr("Tasks")
                onClicked: { if (bar.detailsOpen) bar.backRequested(); App.page = "tasks"; App.unseenFinished = 0 }
            }
            Rectangle {
                visible: App.taskSummary.attention > 0 || App.unseenFinished > 0
                width: 16; height: 16; radius: 8
                anchors.right: parent.right
                anchors.top: parent.top
                color: App.taskSummary.attention > 0 ? Theme.danger : Theme.accentBright
                Text {
                    anchors.centerIn: parent
                    text: App.taskSummary.attention > 0 ? App.taskSummary.attention : App.unseenFinished
                    color: "white"; font.pixelSize: 10; font.weight: Font.Bold
                }
            }
        }

        IconButton {
            iconName: "settings"
            active: App.page === "settings"
            tip: qsTr("Settings (Ctrl+,)")
            onClicked: { if (bar.detailsOpen) bar.backRequested(); App.page = "settings" }
        }

        Text {
            id: clock
            color: Theme.text
            font.pixelSize: 19
            font.weight: Font.Light
            Layout.leftMargin: 6
            text: Qt.formatTime(new Date(), Qt.locale().timeFormat(Locale.ShortFormat))
            Timer {
                interval: 10000
                running: true
                repeat: true
                onTriggered: clock.text = Qt.formatTime(new Date(), Qt.locale().timeFormat(Locale.ShortFormat))
            }
        }
    }
}
