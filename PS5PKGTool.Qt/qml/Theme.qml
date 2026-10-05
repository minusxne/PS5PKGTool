pragma Singleton
import QtQuick

// The PS5-inspired design tokens: deep navy surfaces, PlayStation blue accents, white type,
// generous radii and short eased motion (turned off by "Reduce motion").
QtObject {
    id: theme

    property bool reduceMotion: false
    // False on the software renderer (no GPU), where shader effects are unavailable.
    property bool effects: true

    // Surfaces
    readonly property color background: "#05070b"
    readonly property color backgroundTop: "#0b1120"
    readonly property color surface: Qt.rgba(0.09, 0.11, 0.15, 0.82)
    readonly property color surfaceSolid: "#161b24"
    readonly property color surfaceRaised: "#1f2633"
    readonly property color surfaceHover: Qt.rgba(1, 1, 1, 0.07)
    readonly property color surfacePressed: Qt.rgba(1, 1, 1, 0.12)
    readonly property color outline: Qt.rgba(1, 1, 1, 0.10)
    readonly property color outlineStrong: Qt.rgba(1, 1, 1, 0.22)
    readonly property color scrim: Qt.rgba(0, 0, 0, 0.62)

    // Type
    readonly property color text: "#ffffff"
    readonly property color textDim: Qt.rgba(1, 1, 1, 0.68)
    readonly property color textFaint: Qt.rgba(1, 1, 1, 0.42)

    // Accents and states
    readonly property color accent: "#0070d1"
    readonly property color accentBright: "#2f8cff"
    readonly property color accentSoft: Qt.rgba(0.0, 0.44, 0.82, 0.22)
    readonly property color focus: "#ffffff"
    readonly property color success: "#3ccf8e"
    readonly property color warning: "#f2b84b"
    readonly property color danger: "#ff5a6a"

    // Trophy grades
    readonly property color platinum: "#cfdcea"
    readonly property color gold: "#e8b94a"
    readonly property color silver: "#b9c2cc"
    readonly property color bronze: "#c8834f"

    // Shape
    readonly property int radiusSmall: 8
    readonly property int radius: 12
    readonly property int radiusLarge: 18

    // Spacing
    readonly property int gap: 12
    readonly property int pad: 20
    readonly property int padLarge: 40

    // Type scale (pixels)
    readonly property int fontDisplay: 44
    readonly property int fontTitle: 28
    readonly property int fontHeading: 19
    readonly property int fontBody: 14
    readonly property int fontSmall: 12
    readonly property int fontCaption: 11

    // Motion
    readonly property int fast: reduceMotion ? 0 : 140
    readonly property int normal: reduceMotion ? 0 : 220
    readonly property int slow: reduceMotion ? 0 : 420

    function gradeColor(grade) {
        switch ((grade || "").toLowerCase()) {
        case "platinum": return platinum
        case "gold": return gold
        case "silver": return silver
        case "bronze": return bronze
        }
        return textDim
    }

    function roleColor(role) {
        if (!role) return textDim
        if (role.indexOf("older") >= 0) return warning
        switch (role) {
        case "Base": return accentBright
        case "Update": return success
        case "DLC": return "#b48cff"
        case "App": return "#5fd3e6"
        }
        return textDim
    }

    function formatIcon(format) {
        switch (format) {
        case "PKG": return "package"
        case "exFAT": case "FFPKG": return "drive"
        case "FFPFSC": return "archive"
        }
        return "folder"
    }

    function statusColor(status) {
        switch (status) {
        case "Completed": return success
        case "Failed": case "Interrupted": return danger
        case "Cancelled": case "Cancelling": return warning
        case "Running": return accentBright
        }
        return textDim
    }
}
