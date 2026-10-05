import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// Multi-select filters for category, region and format.
Popup {
    id: popup
    width: 560
    padding: 18
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: Rectangle { radius: Theme.radiusLarge; color: Theme.surfaceRaised; border.color: Theme.outline }

    component FilterColumn: ColumnLayout {
        id: column
        property string title: ""
        property var values: []
        property var selected: []
        signal toggled(string value)
        spacing: 2
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        Text { text: column.title; color: Theme.textDim; font.pixelSize: Theme.fontSmall; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; Layout.bottomMargin: 6 }
        Repeater {
            model: column.values
            delegate: PsCheckBox {
                required property string modelData
                text: modelData
                checked: column.selected.indexOf(modelData) >= 0
                onClicked: column.toggled(modelData)
            }
        }
    }

    contentItem: ColumnLayout {
        spacing: 14
        RowLayout {
            Text { text: qsTr("Filter the library"); color: Theme.text; font.pixelSize: Theme.fontHeading; font.weight: Font.DemiBold; Layout.fillWidth: true }
            PsButton { compact: true; text: qsTr("Reset"); enabled: App.categories.length + App.regions.length + App.formats.length > 0; onClicked: { App.categories = []; App.regions = []; App.formats = [] } }
        }
        RowLayout {
            spacing: 20
            FilterColumn {
                title: qsTr("Category")
                values: App.queryHelp.categories
                selected: App.categories
                onToggled: (value) => App.categories = App.toggleValue(App.categories, value)
            }
            FilterColumn {
                title: qsTr("Region")
                values: App.queryHelp.regions
                selected: App.regions
                onToggled: (value) => App.regions = App.toggleValue(App.regions, value)
            }
            FilterColumn {
                title: qsTr("Format")
                values: App.queryHelp.formats
                selected: App.formats
                onToggled: (value) => App.formats = App.toggleValue(App.formats, value)
            }
        }
    }
}
