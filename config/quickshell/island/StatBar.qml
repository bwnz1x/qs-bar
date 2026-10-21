import QtQuick
import QtQuick.Layouts

// One sideways bar graph row: label + value text on top, bar below.
ColumnLayout {
    id: root
    property string icon: ""
    property string label: ""
    property string value: ""
    property string detail: ""        // optional extra line under the bar
    property real fraction: 0         // 0..1
    property color barColor: Style.text

    spacing: 5

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Text {
            Layout.preferredWidth: 16
            horizontalAlignment: Text.AlignHCenter
            text: root.icon
            color: root.barColor
            font { family: Style.iconFont; pixelSize: 13 }
            Behavior on color { ColorAnimation { duration: 300 } }
        }
        Text {
            text: root.label
            color: Style.dim
            font { family: Style.font; pixelSize: 12; weight: Font.Medium }
        }
        Item { Layout.fillWidth: true }
        Text {
            text: root.value
            color: Style.text
            font { family: Style.font; pixelSize: 13; weight: Font.DemiBold }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        height: 7; radius: 3.5
        color: Style.track
        Rectangle {
            height: parent.height; radius: parent.radius
            width: Math.max(height, parent.width * Math.max(0, Math.min(1, root.fraction)))
            color: root.barColor
            Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 300 } }
        }
    }

    Text {
        visible: root.detail !== ""
        Layout.fillWidth: true
        text: root.detail
        color: Style.dim
        font { family: Style.font; pixelSize: 11; weight: Font.Medium }
    }
}
