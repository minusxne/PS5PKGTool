import QtQuick

// Lazily creates a page the first time it is shown and keeps it alive afterwards, fading
// between pages.
Item {
    id: host
    property string key: ""
    property string source: ""
    property bool visibleWhen: true
    readonly property bool shown: App.page === key && visibleWhen

    anchors.fill: parent
    visible: opacity > 0
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.normal } }

    Loader {
        id: loader
        anchors.fill: parent
        active: false
        source: host.source
        asynchronous: false
        focus: host.shown
    }
    onShownChanged: if (shown) loader.active = true
    Component.onCompleted: if (shown) loader.active = true
}
