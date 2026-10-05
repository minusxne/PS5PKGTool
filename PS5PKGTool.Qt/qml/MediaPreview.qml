import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtMultimedia
import PS5PkgTool.Native

// Audio/video playback for the Files tab (kept separate so a missing QtMultimedia only disables this).
ColumnLayout {
    id: root
    property bool loading: false
    spacing: 10

    function load(gameId, info) {
        loading = true
        App.call("files.materialize", { id: gameId, path: info.path, size: info.size }, function (result) {
            loading = false
            player.source = Desktop.fileUrl(result.file)
        }, function (e) { loading = false; App.showError(qsTr("Could not load media"), e) })
    }

    MediaPlayer {
        id: player
        videoOutput: video
        audioOutput: AudioOutput { volume: volume.value }
        onErrorOccurred: (error, message) => status.text = message
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 8
        color: "black"
        VideoOutput { id: video; anchors.fill: parent }
        Icon { anchors.centerIn: parent; name: "audio"; size: 64; opacity: 0.3; visible: !player.hasVideo }
        PsProgressBar { anchors.centerIn: parent; width: 180; indeterminate: true; visible: root.loading }
    }
    Slider {
        Layout.fillWidth: true
        from: 0
        to: Math.max(1, player.duration)
        value: player.position
        enabled: player.seekable
        onMoved: player.position = value
    }
    RowLayout {
        IconButton { iconName: player.playbackState === MediaPlayer.PlayingState ? "pause" : "play"; enabled: player.source.toString().length > 0; onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play() }
        IconButton { iconName: "stop"; onClicked: player.stop() }
        Text { id: status; text: Qt.formatTime(new Date(player.position), "mm:ss") + " / " + Qt.formatTime(new Date(player.duration), "mm:ss"); color: Theme.textDim; font.pixelSize: Theme.fontSmall + 1; Layout.fillWidth: true }
        Icon { name: "audio"; size: 16; opacity: 0.6 }
        Slider { id: volume; from: 0; to: 1; value: 0.8; Layout.preferredWidth: 120 }
    }
}
