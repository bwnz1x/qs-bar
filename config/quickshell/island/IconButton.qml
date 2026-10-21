import QtQuick

Text {
    id: btn
    signal clicked()
    property real size: 20

    color: Style.text
    font.family: Style.iconFont
    font.pixelSize: size
    opacity: area.containsMouse ? 0.7 : 1
    scale: area.pressed ? 0.85 : 1
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter

    Behavior on scale { NumberAnimation { duration: 120 } }

    MouseArea {
        id: area
        anchors.fill: parent
        anchors.margins: -6
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
