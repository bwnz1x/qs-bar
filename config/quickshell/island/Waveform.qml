import QtQuick

// little animated "now playing" bars
Row {
    id: wf
    property bool playing: true
    property color color: "white"
    property int bars: 5
    property real maxH: 16
    property real barW: 3

    spacing: 2
    height: maxH

    Repeater {
        model: wf.bars
        delegate: Rectangle {
            id: bar
            required property int index
            property real h: 3

            anchors.verticalCenter: parent.verticalCenter
            width: wf.barW
            radius: width / 2
            height: wf.playing ? h : 3
            color: wf.color

            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }
            Behavior on color { ColorAnimation { duration: 400 } }

            Timer {
                interval: 150 + bar.index * 41
                running: wf.playing && wf.visible
                repeat: true
                onTriggered: bar.h = 4 + Math.random() * (wf.maxH - 4)
            }
        }
    }
}
