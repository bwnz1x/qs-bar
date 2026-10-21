pragma Singleton
import QtQuick
import Quickshell

Singleton {
    // picks the most Apple-looking font you have installed
    readonly property string font: {
        const f = Qt.fontFamilies()
        for (const c of ["SF Pro Display", "SF Pro Text", "Inter", "Inter Display", "Noto Sans", "Cantarell"])
            if (f.includes(c)) return c
        return "sans-serif"
    }
    readonly property string iconFont: "MesloLGM Nerd Font Propo"

    readonly property color bg: "#000000"
    readonly property color text: "#ffffff"
    readonly property color dim: "#8e8e93"
    readonly property color track: "#3a3a3c"
    readonly property color green: "#30d158"
    readonly property color orange: "#ff9f0a"
    readonly property color red: "#ff453a"

    readonly property int gap: 6          // distance from the top edge
    readonly property int compactH: 36    // collapsed pill height
}
