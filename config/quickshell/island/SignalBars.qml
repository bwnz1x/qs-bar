import QtQuick

// Cellular-style signal bars: right triangle shape split into vertical sections
Row {
    id: root
    property real signalPercent: 0    // 0 to 100
    property int barCount: 4
    property color activeColor: Style.text
    property color inactiveColor: Style.track
    property real maxBarHeight: 12
    property real barWidth: 3
    property real barSpacing: 1.5

    spacing: barSpacing
    height: maxBarHeight

    Repeater {
        model: root.barCount
        delegate: Rectangle {
            required property int index
            // calculate threshold for each bar (e.g. for 4 bars: 20%, 40%, 60%, 80%)
            readonly property real threshold: ((index + 1) / root.barCount) * 100 - (100 / (root.barCount * 2))
            readonly property bool filled: root.signalPercent > threshold || (index === 0 && root.signalPercent > 5)
            // height increases progressively like a stepped right triangle
            readonly property real h: Math.max(3, (root.maxBarHeight / root.barCount) * (index + 1))

            anchors.bottom: parent.bottom
            width: root.barWidth
            height: h
            radius: root.barWidth / 2
            color: filled ? root.activeColor : root.inactiveColor

            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }
}
