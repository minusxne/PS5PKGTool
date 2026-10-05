import QtQuick
import QtQuick.Controls.Basic

Menu {
    id: menu
    padding: 6
    implicitWidth: 260
    delegate: PsMenuItem {}
    background: Rectangle {
        implicitWidth: 260
        radius: Theme.radius
        color: Theme.surfaceRaised
        border.color: Theme.outline
    }
}
