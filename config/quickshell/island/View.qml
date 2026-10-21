import QtQuick

// A fixed-size content page centred in the island. It fades and scales
// in when `active`, so it gets "revealed" while the island springs open.
Item {
    property bool active: false

    anchors.centerIn: parent
    opacity: active ? 1 : 0
    scale: active ? 1 : 0.92
    visible: opacity > 0.01
    enabled: active

    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.InOutQuad } }
    Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
}
