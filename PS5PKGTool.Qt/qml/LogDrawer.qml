import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import PS5PkgTool.Native

// The activity log (Ctrl+L): everything the engine reports, filterable by level.
Drawer {
    id: drawer
    edge: Qt.BottomEdge
    width: parent ? parent.width : 800
    height: parent ? parent.height * 0.5 : 400
    property string level: "All"
    property bool follow: true

    background: Rectangle { color: Theme.surfaceSolid; Rectangle { width: parent.width; height: 1; color: Theme.outline } }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 10
        RowLayout {
            Text { text: qsTr("Activity log"); color: Theme.text; font.pixelSize: Theme.fontHeading; font.weight: Font.DemiBold }
            Item { implicitWidth: 12 }
            Repeater {
                model: ["All", "Info", "Warn", "Error", "Engine"]
                delegate: Chip { required property string modelData; text: modelData; selected: drawer.level === modelData; onClicked: drawer.level = modelData }
            }
            Item { Layout.fillWidth: true }
            PsCheckBox { text: qsTr("Follow"); checked: drawer.follow; onToggled: drawer.follow = checked }
            PsButton { compact: true; iconName: "copy"; text: qsTr("Copy"); onClicked: { const lines = []; for (let i = 0; i < App.logModel.count; ++i) { const e = App.logModel.get(i); lines.push(e.time + " [" + e.level + "] " + e.message) } App.copy(lines.join("\n"), qsTr("Log")) } }
            PsButton { compact: true; iconName: "folder"; text: qsTr("Log folder"); onClicked: Desktop.openPath(App.hello.logDirectory) }
            PsButton { compact: true; iconName: "broom"; text: qsTr("Clear"); onClicked: App.logModel.clear() }
            IconButton { iconName: "close"; onClicked: drawer.close() }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radius
            color: Qt.rgba(0, 0, 0, 0.35)
            ListView {
                id: logList
                anchors.fill: parent
                anchors.margins: 10
                clip: true
                model: App.logModel
                ScrollBar.vertical: ScrollBar {}
                onCountChanged: if (drawer.follow) positionViewAtEnd()
                delegate: Text {
                    required property string time
                    required property string level
                    required property string message
                    readonly property bool shown: drawer.level === "All" || level === drawer.level || (drawer.level === "Engine" && (level === "Engine" || level === "File"))
                    visible: shown
                    height: shown ? implicitHeight : 0
                    width: ListView.view.width
                    text: time + "  " + message
                    color: level === "Error" ? Theme.danger : level === "Warn" ? Theme.warning : level === "Engine" || level === "File" ? Theme.textFaint : Theme.textDim
                    font.family: "monospace"
                    font.pixelSize: Theme.fontSmall
                    wrapMode: Text.WrapAnywhere
                }
            }
        }
    }
}
