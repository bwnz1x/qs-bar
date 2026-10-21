import QtQuick

// Battery glyph whose inner fill really reflects the charge level.
Item {
    id: root
    property real percent: 100
    property bool charging: false
    property color color: "white"
    property real iconHeight: 12

    implicitWidth: iconHeight * 2 + 3
    implicitHeight: iconHeight

    readonly property real frac: Math.max(0, Math.min(1, percent / 100))

    Rectangle {
        id: body
        width: parent.width - 3
        height: parent.height
        radius: height * 0.3
        color: "transparent"
        border { width: 1.5; color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.55) }

        Rectangle {
            x: 2.5; y: 2.5
            height: parent.height - 5
            width: Math.max(frac > 0 ? height * 0.5 : 0, (parent.width - 5) * root.frac)
            radius: height * 0.2
            color: root.color
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }
        Text {
            visible: root.charging
            anchors.centerIn: parent
            text: "\uf0e7"
            font { family: Style.iconFont; pixelSize: root.iconHeight * 0.75 }
            color: "#000000"
            style: Text.Outline
            styleColor: "#ffffff"
        }
    }
    // terminal nub
    Rectangle {
        anchors { left: body.right; leftMargin: 0.5; verticalCenter: parent.verticalCenter }
        width: 2; height: root.height * 0.4
        radius: 1
        color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.55)
    }
}
