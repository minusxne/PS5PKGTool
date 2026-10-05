import QtQuick

// A wrapping row that is safe inside layouts: its height follows the wrapped content without
// feeding back into the layout's width calculation.
Item {
    default property alias content: flow.data
    property alias spacing: flow.spacing
    implicitWidth: 120
    implicitHeight: flow.implicitHeight
    Flow {
        id: flow
        width: parent.width
    }
}
