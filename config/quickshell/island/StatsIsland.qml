import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower

// Top-left island: RAM, CPU temperature, battery.
PanelWindow {
    id: win
    required property var modelData
    screen: modelData

    anchors { top: true; left: true }
    margins.left: 12
    implicitWidth: 400
    implicitHeight: 240
    exclusiveZone: -1                     // -1 = ignore the main island's reserved strip so we start at the screen top too
    color: "transparent"
    WlrLayershell.namespace: "dynamic-island-stats"
    WlrLayershell.layer: WlrLayer.Top

    mask: Region { item: island }

    // ───────────────────────── data ─────────────────────────

    property real memTotalKb: 0
    property real memAvailKb: 0
    property real cpuTemp: 0

    readonly property real memUsedGb: (memTotalKb - memAvailKb) / 1048576
    readonly property real memTotalGb: memTotalKb / 1048576
    readonly property real memFrac: memTotalKb > 0 ? (memTotalKb - memAvailKb) / memTotalKb : 0

    // reads RAM from /proc/meminfo and the CoreTemp package sensor (hwmon index varies)
    Process {
        id: poll
        command: ["sh", "-c",
            "t=0; for h in /sys/class/hwmon/hwmon*; do " +
            "if [ \"$(cat $h/name 2>/dev/null)\" = coretemp ]; then t=$(cat $h/temp1_input); break; fi; done; " +
            "[ \"$t\" = 0 ] && for h in /sys/class/hwmon/hwmon*; do " +
            "case \"$(cat $h/name 2>/dev/null)\" in k10temp|zenpower) t=$(cat $h/temp1_input); break;; esac; done; " +
            "awk -v t=$t '/MemTotal/{a=$2} /MemAvailable/{b=$2} END{print a, b, t}' /proc/meminfo"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(/\s+/).map(Number)
                if (p.length < 3) return
                win.memTotalKb = p[0]
                win.memAvailKb = p[1]
                win.cpuTemp = p[2] / 1000
            }
        }
    }
    Timer {
        interval: 2000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: if (!poll.running) poll.running = true
    }

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery?.isLaptopBattery ?? false
    readonly property real batPct: {
        const p = battery?.percentage ?? 0
        return p <= 1 ? p * 100 : p
    }
    readonly property bool charging: battery?.state === UPowerDeviceState.Charging
    readonly property bool full: battery?.state === UPowerDeviceState.FullyCharged
    readonly property real watts: Math.abs(battery?.changeRate ?? 0)

    function levelColor(frac) {      // for RAM and temperature
        return frac < 0.7 ? Style.green : frac < 0.85 ? Style.orange : Style.red
    }
    readonly property color batColor:
        (charging || full) ? Style.green : batPct <= 20 ? Style.red : batPct <= 40 ? Style.orange : Style.text

    function fmtTime(sec) {
        if (!sec || sec <= 0) return ""
        const h = Math.floor(sec / 3600), m = Math.round((sec % 3600) / 60)
        return h > 0 ? h + "h " + m + "m" : m + "m"
    }
    readonly property string batDetail: {
        if (full) return "Fully charged"
        const w = watts.toFixed(1) + " W"
        const t = charging ? fmtTime(battery?.timeToFull) : fmtTime(battery?.timeToEmpty)
        if (t === "") return w + (charging ? " charging" : " draw")
        return w + (charging ? "  ·  " + t + " until full" : "  ·  " + t + " left")
    }

    // ───────────────────────── state ─────────────────────────

    property bool expanded: false
    Timer { id: expandTimer; interval: 180; onTriggered: win.expanded = true }
    Timer { id: collapseTimer; interval: 350; onTriggered: win.expanded = false }

    // ───────────────────────── the island ─────────────────────────

    Rectangle {
        id: island
        x: 0
        y: Style.gap
        width: win.expanded ? 340 : 190
        height: win.expanded ? (win.hasBattery ? 188 : 120) : Style.compactH
        radius: Math.min(height / 2, 36)
        color: Style.bg
        clip: true

        Behavior on width  { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

        HoverHandler {
            onHoveredChanged: {
                if (hovered) { collapseTimer.stop(); expandTimer.restart() }
                else { expandTimer.stop(); collapseTimer.restart() }
            }
        }

        // ── idle ──
        View {
            active: !win.expanded
            width: 190 - 24
            height: Style.compactH

            Row {
                anchors.fill: parent
                spacing: 0

                Item {
                    width: parent.width / 3; height: parent.height
                    Row {
                        anchors.centerIn: parent
                        spacing: 8
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\uf2db"
                            color: Style.dim
                            font { family: Style.iconFont; pixelSize: 11 }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Math.round(win.memFrac * 100) + "%"
                            color: Style.text
                            font { family: Style.font; pixelSize: 13; weight: Font.DemiBold }
                        }
                    }
                }
                Item {
                    width: parent.width / 3; height: parent.height
                    Row {
                        anchors.centerIn: parent
                        spacing: 8
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\uf2c9"
                            color: Style.dim
                            font { family: Style.iconFont; pixelSize: 12 }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Math.round(win.cpuTemp) + "°"
                            color: Style.text
                            font { family: Style.font; pixelSize: 13; weight: Font.DemiBold }
                        }
                    }
                }
                Item {
                    width: parent.width / 3 + 4; height: parent.height
                    BatteryIcon {
                        visible: win.hasBattery
                        anchors.centerIn: parent
                        percent: win.batPct
                        charging: win.charging
                        color: win.batColor
                        iconHeight: 12
                    }
                }
            }
        }

        // ── expanded: three sideways bar graphs ──
        View {
            active: win.expanded
            width: 340 - 40
            height: island.height - 32

            ColumnLayout {
                anchors.fill: parent
                spacing: 14

                StatBar {
                    Layout.fillWidth: true
                    icon: "\uf2db"
                    label: "Memory"
                    value: win.memUsedGb.toFixed(1) + " / " + win.memTotalGb.toFixed(1) + " GB"
                    fraction: win.memFrac
                    barColor: win.levelColor(win.memFrac)
                }
                StatBar {
                    Layout.fillWidth: true
                    icon: "\uf2c9"
                    label: "CPU Temp"
                    value: Math.round(win.cpuTemp) + " °C"
                    fraction: win.cpuTemp / 100          // 0 – 100 °C
                    barColor: win.levelColor(win.cpuTemp / 100)
                }
                StatBar {
                    visible: win.hasBattery
                    Layout.fillWidth: true
                    icon: win.charging ? "\uf0e7" : "\uf240"
                    label: "Battery"
                    value: Math.round(win.batPct) + "%"
                    detail: win.batDetail
                    fraction: win.batPct / 100
                    barColor: win.batColor
                }
            }
        }
    }
}
