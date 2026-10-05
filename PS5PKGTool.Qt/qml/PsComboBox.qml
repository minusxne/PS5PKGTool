import QtQuick
import QtQuick.Controls.Basic

ComboBox {
    id: control
    implicitHeight: 42
    implicitWidth: 220
    hoverEnabled: true
    font.pixelSize: Theme.fontBody

    delegate: ItemDelegate {
        id: entry
        required property var model
        required property int index
        width: control.popup.width - 12
        x: 6
        height: 38
        highlighted: control.highlightedIndex === index
        contentItem: Text {
            text: entry.model[control.textRole] !== undefined ? entry.model[control.textRole] : entry.model.modelData
            color: Theme.text
            font.pixelSize: Theme.fontBody
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            leftPadding: 6
        }
        background: Rectangle {
            radius: 8
            color: entry.highlighted ? Theme.accent : entry.hovered ? Theme.surfaceHover : "transparent"
        }
    }

    indicator: Icon {
        x: control.width - width - 12
        y: (control.height - height) / 2
        name: "chevron-down"
        size: 16
        opacity: 0.7
    }

    contentItem: Text {
        leftPadding: 14
        rightPadding: 34
        text: control.displayText
        color: Theme.text
        font: control.font
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Rectangle {
        radius: Theme.radiusSmall + 2
        color: control.pressed ? Theme.surfacePressed : control.hovered ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(1, 1, 1, 0.07)
        border.width: control.visualFocus ? 2 : 1
        border.color: control.visualFocus ? Theme.accentBright : Theme.outline
    }

    popup: Popup {
        y: control.height + 4
        width: Math.max(control.width, 200)
        implicitHeight: Math.min(contentItem.implicitHeight + 12, 360)
        padding: 6
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator {}
        }
        background: Rectangle {
            radius: Theme.radius
            color: Theme.surfaceRaised
            border.color: Theme.outline
        }
    }
}
