import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Bluetooth

PanelWindow {
    id: win
    required property var modelData
    screen: modelData

    anchors { top: true; right: true }
    margins.right: 12
    implicitWidth: 420
    implicitHeight: 520
    exclusiveZone: -1                     // overlay without displacing windows
    color: "transparent"
    WlrLayershell.namespace: "dynamic-island-control"
    WlrLayershell.layer: WlrLayer.Top

    mask: Region { item: island }

    // ───────────────────────── State & Tab Navigation ─────────────────────────

    property bool expanded: false
    // Active menu tab: "wifi", "bluetooth", "actions"
    property string activeTab: "actions"

    Timer { id: expandTimer; interval: 180; onTriggered: win.expanded = true }
    Timer { id: collapseTimer; interval: 350; onTriggered: win.expanded = false }

    // ───────────────────────── Wi-Fi / Ethernet Data ─────────────────────────

    property string ethStatus: "disconnected" // connected, disconnected
    property string wifiSsid: ""
    property int wifiSignal: 0
    property bool wifiConnected: false
    property var networks: []
    property string pendingSsid: ""
    property string pendingPassword: ""
    property string wifiMessage: ""
    property bool wifiScanning: false

    // Quick active Wi-Fi / Ethernet state poll
    Process {
        id: netStatusProc
        command: ["sh", "-c", "eth=$(nmcli -t -f TYPE,STATE dev status | grep '^ethernet:connected'); if [ -n \"$eth\" ]; then echo \"ETH\"; else nmcli -t -f active,ssid,signal dev wifi | grep '^yes:' | head -1; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const line = text.trim()
                if (line === "ETH") {
                    win.ethStatus = "connected"
                    win.wifiConnected = false
                } else if (line.startsWith("yes:")) {
                    win.ethStatus = "disconnected"
                    win.wifiConnected = true
                    const parts = line.split(":")
                    win.wifiSsid = parts[1] || ""
                    win.wifiSignal = parseInt(parts[2]) || 0
                } else {
                    win.ethStatus = "disconnected"
                    win.wifiConnected = false
                    win.wifiSsid = ""
                    win.wifiSignal = 0
                }
            }
        }
    }

    Timer {
        interval: 4000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: if (!netStatusProc.running) netStatusProc.running = true
    }

    // Wi-Fi list scanner
    Process {
        id: listWifiProc
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "dev", "wifi", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                win.wifiScanning = false
                const best = {}
                for (const line of text.trim().split("\n")) {
                    if (!line) continue
                    const f = line.replace(/\\:/g, "\u0001").split(":").map(s => s.replace(/\u0001/g, ":"))
                    const ssid = f[1]
                    if (!ssid) continue
                    const n = { ssid: ssid, signal: parseInt(f[2]) || 0, secure: f[3] !== "" && f[3] !== "--", active: f[0] === "*" }
                    const o = best[ssid]
                    if (!o || n.active || (!o.active && n.signal > o.signal)) best[ssid] = n
                }
                win.networks = Object.values(best).sort((a, b) => (b.active - a.active) || (b.signal - a.signal))
            }
        }
    }

    Process {
        id: rescanWifiProc
        command: ["nmcli", "dev", "wifi", "rescan"]
        onExited: listWifiProc.running = true
    }

    function scanWifi() {
        win.wifiScanning = true
        rescanWifiProc.running = true
    }

    readonly property string connectScript: [
        "saved=$(nmcli -t -f NAME,TYPE con show | sed -n 's/:802-11-wireless$//p' | while IFS= read -r n; do",
        "  [ \"$(nmcli -g 802-11-wireless.ssid con show \"$n\" 2>/dev/null)\" = \"$1\" ] && { echo \"$n\"; break; }",
        "done)",
        "if [ -n \"$2\" ]; then nmcli dev wifi connect \"$1\" password \"$2\"",
        "elif [ -n \"$saved\" ]; then nmcli con up \"$saved\"",
        "else nmcli dev wifi connect \"$1\"; fi"
    ].join("\n")

    Process {
        id: connectWifiProc
        property string targetSsid
        property string targetPw
        command: ["sh", "-c", win.connectScript, "sh", targetSsid, targetPw]
        stderr: StdioCollector { id: connErr }
        onExited: (code) => {
            if (code === 0) {
                win.wifiMessage = ""
                win.pendingSsid = ""
                win.pendingPassword = ""
                netStatusProc.running = true
                listWifiProc.running = true
            } else if (!targetPw && win.networks.find(n => n.ssid === targetSsid)?.secure) {
                win.wifiMessage = ""
                win.pendingSsid = targetSsid
            } else {
                win.wifiMessage = connErr.text.trim().split("\n")[0] || ("Could not connect to " + targetSsid)
            }
        }
    }

    function connectToWifi(ssid, pw) {
        win.wifiMessage = "Connecting to " + ssid + "..."
        connectWifiProc.targetSsid = ssid
        connectWifiProc.targetPw = pw
        connectWifiProc.running = true
    }

    // ───────────────────────── Bluetooth Data ─────────────────────────

    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property bool btEnabled: btAdapter?.enabled ?? false

    // Bluetooth discovery mode state
    property bool btScanning: false

    readonly property var allBtDevices: Bluetooth.devices.values
    readonly property var connectedBtDevices: allBtDevices.filter(d => d.connected)
    readonly property var pairedBtDevices: allBtDevices.filter(d => d.paired && !d.connected)

    // Discovered devices: filtered to only those with a friendly name and not a raw MAC address
    readonly property var discoveredBtDevices: {
        if (!btScanning) return []
        return allBtDevices.filter(d => {
            if (d.connected || d.paired) return false
            const n = (d.name || "").trim()
            if (!n) return false
            // ignore if name is just MAC address XX:XX:XX:XX:XX:XX or XX-XX-XX-XX-XX-XX
            if (/^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$/.test(n)) return false
            return true
        })
    }

    readonly property string btStatusText: {
        const count = connectedBtDevices.length
        if (count === 0) return ""
        if (count === 1) return connectedBtDevices[0].name || "Connected"
        return count + " Devices"
    }

    // Scan timer: stop discovering automatically after 20 seconds
    Timer {
        id: btScanTimeout
        interval: 20000
        onTriggered: {
            win.btScanning = false
            if (win.btAdapter) win.btAdapter.discovering = false
        }
    }

    function toggleBtScan() {
        if (!win.btScanning) {
            win.btScanning = true
            if (win.btAdapter) win.btAdapter.discovering = true
            btScanTimeout.restart()
        } else {
            win.btScanning = false
            if (win.btAdapter) win.btAdapter.discovering = false
            btScanTimeout.stop()
        }
    }

    function connectBtDevice(device) {
        if (device.connected) {
            device.disconnect()
        } else if (device.paired) {
            device.connect()
        } else {
            // Pair & connect newly discovered device
            device.pair()
            // Turn off scanning mode once user selects device
            win.btScanning = false
            if (win.btAdapter) win.btAdapter.discovering = false
        }
    }

    // ───────────────────────── General Actions / DND ─────────────────────────

    property bool dndEnabled: false

    Process {
        id: toggleWifiPowerProc
        property bool turnOn: true
        command: ["nmcli", "radio", "wifi", turnOn ? "on" : "off"]
        onExited: netStatusProc.running = true
    }

    Process {
        id: unblockBtProc
        command: ["rfkill", "unblock", "bluetooth"]
        onExited: enableBtTimer.start()
    }
    Timer {
        id: enableBtTimer
        interval: 500
        onTriggered: if (win.btAdapter) win.btAdapter.enabled = true
    }

    function setBtPower(enable) {
        if (enable) unblockBtProc.running = true
        else if (win.btAdapter) win.btAdapter.enabled = false
    }

    Process {
        id: wlogoutProc
        command: ["wlogout"]
    }

    // ───────────────────────── Lenovo Legion Controls ─────────────────────────

    // Power Profile: "power-saver" (blue), "balanced" (white), "performance" (red)
    property string legionPowerProfile: "power-saver"

    Process {
        id: readProfileProc
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim()
                if (p === "performance" || p === "balanced" || p === "power-saver") {
                    win.legionPowerProfile = p
                }
            }
        }
    }

    Process {
        id: setProfileProc
        property string targetProfile: "balanced"
        command: ["powerprofilesctl", "set", targetProfile]
        onExited: readProfileProc.running = true
    }

    function cyclePowerProfile() {
        if (legionPowerProfile === "power-saver") setProfileProc.targetProfile = "balanced"
        else if (legionPowerProfile === "balanced") setProfileProc.targetProfile = "performance"
        else setProfileProc.targetProfile = "power-saver"
        setProfileProc.running = true
    }

    // Touchpad Enable/Disable state
    property bool touchpadEnabled: true

    Process {
        id: toggleTouchpadProc
        property bool targetState: true
        command: ["hyprctl", "repl", "return hl.device({ name = \"ftcs0038:00-2808:0106-touchpad\", enabled = " + (targetState ? "true" : "false") + " })"]
    }

    function toggleTouchpad() {
        win.touchpadEnabled = !win.touchpadEnabled
        toggleTouchpadProc.targetState = win.touchpadEnabled
        toggleTouchpadProc.running = true
    }

    // Fan RPM speeds (fan1 and fan2 from lenovo_wmi_other hwmon)
    property int fan1Rpm: 0
    property int fan2Rpm: 0

    Process {
        id: fanRpmProc
        command: ["sh", "-c", "for h in /sys/class/hwmon/hwmon*; do if [ \"$(cat $h/name 2>/dev/null)\" = \"lenovo_wmi_other\" ]; then echo \"$(cat $h/fan1_input 2>/dev/null || echo 0) $(cat $h/fan2_input 2>/dev/null || echo 0)\"; exit; fi; done; echo \"0 0\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(/\s+/).map(Number)
                if (parts.length >= 2) {
                    win.fan1Rpm = parts[0] || 0
                    win.fan2Rpm = parts[1] || 0
                }
            }
        }
    }

    Timer {
        interval: 3000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            if (!readProfileProc.running) readProfileProc.running = true
            if (win.expanded && !fanRpmProc.running) fanRpmProc.running = true
        }
    }

    // ───────────────────────── Dimensions ─────────────────────────

    // Dynamic width based exactly on content with 28px horizontal padding (14px on each side)
    readonly property int idleW: (typeof idleContent !== "undefined" && idleContent ? idleContent.width : 100) + 28

    // ───────────────────────── The Island Frame ─────────────────────────

    Rectangle {
        id: island
        anchors.right: parent.right
        y: Style.gap
        width: win.expanded ? 360 : win.idleW
        height: win.expanded ? 450 : Style.compactH
        radius: Math.min(height / 2, 34)
        color: Style.bg
        clip: true

        Behavior on width  { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

        HoverHandler {
            onHoveredChanged: {
                if (hovered) {
                    collapseTimer.stop()
                    expandTimer.restart()
                    if (win.networks.length === 0) listWifiProc.running = true
                } else {
                    expandTimer.stop()
                    collapseTimer.restart()
                }
            }
        }

        // ═════════════════════════ IDLE VIEW ═════════════════════════
        View {
            active: !win.expanded
            width: idleContent.width
            height: Style.compactH

            Row {
                id: idleContent
                anchors.centerIn: parent
                spacing: 10

                // Wi-Fi / Ethernet Section
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.ethStatus === "connected" ? "\uf796" : (win.wifiConnected ? "" : "\uf1eb")
                        visible: win.ethStatus === "connected" || !win.wifiConnected
                        color: (win.ethStatus === "connected" || win.wifiConnected) ? Style.text : Style.dim
                        font { family: Style.iconFont; pixelSize: 13 }
                    }

                    SignalBars {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: win.ethStatus !== "connected" && win.wifiConnected
                        signalPercent: win.wifiSignal
                        activeColor: Style.text
                        inactiveColor: Style.track
                        maxBarHeight: 12
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.ethStatus === "connected" ? "Ethernet" : (win.wifiSsid || "Offline")
                        color: (win.ethStatus === "connected" || win.wifiConnected) ? Style.text : Style.dim
                        font { family: Style.font; pixelSize: 12; weight: Font.Medium }
                    }
                }

                // Bluetooth section (only shown when device is connected)
                Row {
                    id: btRow
                    visible: win.connectedBtDevices.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Rectangle {
                        width: 1; height: 12
                        color: Style.track
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\uf293"
                        color: "#007aff"
                        font { family: Style.iconFont; pixelSize: 13 }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.btStatusText
                        color: Style.text
                        font { family: Style.font; pixelSize: 12; weight: Font.Medium }
                    }
                }
            }
        }

        // ═════════════════════════ EXPANDED MENU ═════════════════════════
        View {
            active: win.expanded
            width: 360 - 32
            height: 450 - 28

            ColumnLayout {
                anchors.fill: parent
                spacing: 12

                // ── Top Navigation Tabs ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    // Wi-Fi Tab Button
                    Rectangle {
                        Layout.fillWidth: true
                        height: 30
                        radius: 8
                        color: win.activeTab === "wifi" ? "#2c2c2e" : (wTabMa.containsMouse ? "#1c1c1e" : "transparent")
                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: "\uf1eb"
                                color: win.wifiConnected ? Style.green : Style.text
                                font { family: Style.iconFont; pixelSize: 12 }
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "Wi-Fi"
                                color: win.activeTab === "wifi" ? Style.text : Style.dim
                                font { family: Style.font; pixelSize: 12; weight: win.activeTab === "wifi" ? Font.DemiBold : Font.Normal }
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea {
                            id: wTabMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.activeTab = "wifi"
                        }
                    }

                    // Bluetooth Tab Button
                    Rectangle {
                        Layout.fillWidth: true
                        height: 30
                        radius: 8
                        color: win.activeTab === "bluetooth" ? "#2c2c2e" : (bTabMa.containsMouse ? "#1c1c1e" : "transparent")
                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: "\uf293"
                                color: win.btEnabled ? "#007aff" : Style.dim
                                font { family: Style.iconFont; pixelSize: 12 }
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "Bluetooth"
                                color: win.activeTab === "bluetooth" ? Style.text : Style.dim
                                font { family: Style.font; pixelSize: 12; weight: win.activeTab === "bluetooth" ? Font.DemiBold : Font.Normal }
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea {
                            id: bTabMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.activeTab = "bluetooth"
                        }
                    }

                    // Actions Tab Button
                    Rectangle {
                        Layout.fillWidth: true
                        height: 30
                        radius: 8
                        color: win.activeTab === "actions" ? "#2c2c2e" : (aTabMa.containsMouse ? "#1c1c1e" : "transparent")
                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: "\uf013"
                                color: Style.text
                                font { family: Style.iconFont; pixelSize: 12 }
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "Controls"
                                color: win.activeTab === "actions" ? Style.text : Style.dim
                                font { family: Style.font; pixelSize: 12; weight: win.activeTab === "actions" ? Font.DemiBold : Font.Normal }
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea {
                            id: aTabMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.activeTab = "actions"
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Style.track
                }

                // ── TAB 1: WI-FI MENU ──
                ColumnLayout {
                    visible: win.activeTab === "wifi"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Available Networks"
                            color: Style.dim
                            font { family: Style.font; pixelSize: 11; weight: Font.DemiBold }
                            Layout.fillWidth: true
                        }
                        IconButton {
                            text: "\uf021"
                            size: 13
                            color: win.wifiScanning ? Style.green : Style.dim
                            onClicked: win.scanWifi()
                        }
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 4
                        model: win.networks

                        delegate: Column {
                            id: netItem
                            required property var modelData
                            width: ListView.view.width
                            spacing: 3

                            Rectangle {
                                width: parent.width
                                height: 36
                                radius: 8
                                color: netItem.modelData.active ? "#25342a" : (netMa.containsMouse ? "#1c1c1e" : "transparent")

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8; anchors.rightMargin: 8
                                    spacing: 8

                                    SignalBars {
                                        signalPercent: netItem.modelData.signal
                                        activeColor: netItem.modelData.active ? Style.green : Style.text
                                        inactiveColor: Style.track
                                        maxBarHeight: 11
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: netItem.modelData.ssid
                                        color: netItem.modelData.active ? Style.green : Style.text
                                        font { family: Style.font; pixelSize: 12; weight: netItem.modelData.active ? Font.DemiBold : Font.Normal }
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        visible: netItem.modelData.secure
                                        text: "\uf023"
                                        color: Style.dim
                                        font { family: Style.iconFont; pixelSize: 11 }
                                    }
                                }

                                MouseArea {
                                    id: netMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (netItem.modelData.active) return
                                        if (netItem.modelData.secure) {
                                            if (win.pendingSsid === netItem.modelData.ssid) {
                                                win.pendingSsid = ""
                                            } else {
                                                win.pendingSsid = netItem.modelData.ssid
                                                win.pendingPassword = ""
                                            }
                                        } else {
                                            win.connectToWifi(netItem.modelData.ssid, "")
                                        }
                                    }
                                }
                            }

                            // Password Input Prompt for Secured Networks
                            Rectangle {
                                visible: win.pendingSsid === netItem.modelData.ssid
                                width: parent.width
                                height: 34
                                radius: 6
                                color: "#22ffffff"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8; anchors.rightMargin: 6

                                    TextInput {
                                        id: pwInput
                                        Layout.fillWidth: true
                                        echoMode: TextInput.Password
                                        color: Style.text
                                        font { family: Style.font; pixelSize: 12 }
                                        focus: visible
                                        onAccepted: win.connectToWifi(netItem.modelData.ssid, text)

                                        Text {
                                            visible: parent.text === ""
                                            text: "Enter Wi-Fi Password..."
                                            color: Style.dim
                                            font: parent.font
                                        }
                                    }

                                    IconButton {
                                        text: "\uf00c"
                                        size: 13
                                        color: Style.green
                                        onClicked: win.connectToWifi(netItem.modelData.ssid, pwInput.text)
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        visible: win.wifiMessage !== ""
                        text: win.wifiMessage
                        color: Style.orange
                        font { family: Style.font; pixelSize: 11 }
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                // ── TAB 2: BLUETOOTH MENU ──
                ColumnLayout {
                    visible: win.activeTab === "bluetooth"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: !win.btEnabled ? "Bluetooth is Off" : (win.btScanning ? "Scanning for devices..." : "Bluetooth Devices")
                            color: Style.dim
                            font { family: Style.font; pixelSize: 11; weight: Font.DemiBold }
                            Layout.fillWidth: true
                        }

                        // Scan Toggle Button (search icon)
                        IconButton {
                            visible: win.btEnabled
                            text: "\uf002"
                            size: 13
                            color: win.btScanning ? Style.green : Style.dim
                            onClicked: win.toggleBtScan()
                        }
                    }

                    // Device List
                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 4
                        // When scanning: display discovered devices only (clearing paired/connected to give space)
                        // When not scanning: display connected first, followed by paired
                        model: win.btScanning ? win.discoveredBtDevices : win.connectedBtDevices.concat(win.pairedBtDevices)

                        delegate: Rectangle {
                            id: btItem
                            required property var modelData
                            width: ListView.view.width
                            height: 40
                            radius: 8
                            color: modelData.connected ? "#1e2e3d" : (btMa.containsMouse ? "#1c1c1e" : "transparent")

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8; anchors.rightMargin: 8
                                spacing: 10

                                Text {
                                    text: "\uf293"
                                    color: btItem.modelData.connected ? "#007aff" : Style.dim
                                    font { family: Style.iconFont; pixelSize: 14 }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Text {
                                        Layout.fillWidth: true
                                        text: btItem.modelData.name || btItem.modelData.address
                                        color: btItem.modelData.connected ? "#007aff" : Style.text
                                        font { family: Style.font; pixelSize: 12; weight: btItem.modelData.connected ? Font.DemiBold : Font.Normal }
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: btItem.modelData.connected ? "Connected" : (btItem.modelData.paired ? "Paired" : "Discovered")
                                        color: Style.dim
                                        font { family: Style.font; pixelSize: 10 }
                                    }
                                }

                                Text {
                                    visible: btItem.modelData.batteryAvailable
                                    text: Math.round(btItem.modelData.battery * 100) + "%"
                                    color: Style.dim
                                    font { family: Style.font; pixelSize: 11 }
                                }
                            }

                            MouseArea {
                                id: btMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.connectBtDevice(btItem.modelData)
                            }
                        }
                    }
                }

                // ── TAB 3: ACTIONS & CONTROLS ──
                ColumnLayout {
                    visible: win.activeTab === "actions"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 12

                    Text {
                        text: "Quick Controls"
                        color: Style.dim
                        font { family: Style.font; pixelSize: 11; weight: Font.DemiBold }
                    }

                    // Single horizontal row of 4 Action Buttons (Apple Control Center style)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        // Wi-Fi Toggle Button
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: width
                            radius: 16
                            color: win.wifiConnected ? "#243328" : "#1c1c1e"

                            Rectangle {
                                anchors.centerIn: parent
                                width: Math.min(42, parent.width - 16)
                                height: width
                                radius: width / 2
                                color: win.wifiConnected ? Style.green : "#2c2c2e"
                                Text {
                                    anchors.centerIn: parent
                                    text: "\uf1eb"
                                    color: win.wifiConnected ? "#000000" : Style.text
                                    font { family: Style.iconFont; pixelSize: 16 }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    toggleWifiPowerProc.turnOn = !win.wifiConnected
                                    toggleWifiPowerProc.running = true
                                }
                            }
                        }

                        // Bluetooth Toggle Button
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: width
                            radius: 16
                            color: win.btEnabled ? "#1a2c3d" : "#1c1c1e"

                            Rectangle {
                                anchors.centerIn: parent
                                width: Math.min(42, parent.width - 16)
                                height: width
                                radius: width / 2
                                color: win.btEnabled ? "#007aff" : "#2c2c2e"
                                Text {
                                    anchors.centerIn: parent
                                    text: "\uf293"
                                    color: win.btEnabled ? "#ffffff" : Style.text
                                    font { family: Style.iconFont; pixelSize: 16 }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.setBtPower(!win.btEnabled)
                            }
                        }

                        // Do Not Disturb (DND) Button
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: width
                            radius: 16
                            color: win.dndEnabled ? "#3a2b16" : "#1c1c1e"

                            Rectangle {
                                anchors.centerIn: parent
                                width: Math.min(42, parent.width - 16)
                                height: width
                                radius: width / 2
                                color: win.dndEnabled ? Style.orange : "#2c2c2e"
                                Text {
                                    anchors.centerIn: parent
                                    text: "\uf1f6"
                                    color: win.dndEnabled ? "#000000" : Style.text
                                    font { family: Style.iconFont; pixelSize: 16 }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.dndEnabled = !win.dndEnabled
                            }
                        }

                        // Power Options (wlogout) Button
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: width
                            radius: 16
                            color: "#1c1c1e"

                            Rectangle {
                                anchors.centerIn: parent
                                width: Math.min(42, parent.width - 16)
                                height: width
                                radius: width / 2
                                color: "#2c2c2e"
                                Text {
                                    anchors.centerIn: parent
                                    text: "\uf011"
                                    color: Style.red
                                    font { family: Style.iconFont; pixelSize: 16 }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    win.expanded = false
                                    wlogoutProc.running = true
                                }
                            }
                        }
                    }

                    // ── SECTION: LEGION CONTROL ──
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Style.track
                        Layout.topMargin: 4
                        Layout.bottomMargin: 2
                    }

                    Text {
                        text: "Legion Control"
                        color: Style.dim
                        font { family: Style.font; pixelSize: 11; weight: Font.DemiBold }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        // 1. Power Mode Selection Button (Quiet = Blue, Balanced = White, Performance = Red)
                        Rectangle {
                            Layout.preferredWidth: 60
                            Layout.preferredHeight: 60
                            radius: 14
                            color: win.legionPowerProfile === "power-saver" ? "#14253d" : (win.legionPowerProfile === "performance" ? "#3b1e1e" : "#2a2a2c")

                            Rectangle {
                                anchors.centerIn: parent
                                width: 38; height: 38; radius: 19
                                color: win.legionPowerProfile === "power-saver" ? "#0a84ff" : (win.legionPowerProfile === "performance" ? Style.red : "#ffffff")

                                Text {
                                    anchors.centerIn: parent
                                    text: "\uf0e7"
                                    color: win.legionPowerProfile === "balanced" ? "#000000" : "#ffffff"
                                    font { family: Style.iconFont; pixelSize: 16 }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.cyclePowerProfile()
                            }
                        }

                        // 2. Touchpad Toggle Button
                        Rectangle {
                            Layout.preferredWidth: 60
                            Layout.preferredHeight: 60
                            radius: 14
                            color: win.touchpadEnabled ? "#1e2e3d" : "#1c1c1e"

                            Rectangle {
                                anchors.centerIn: parent
                                width: 38; height: 38; radius: 19
                                color: win.touchpadEnabled ? "#007aff" : "#2c2c2e"

                                Text {
                                    anchors.centerIn: parent
                                    text: "\uf245"
                                    color: win.touchpadEnabled ? "#ffffff" : Style.dim
                                    font { family: Style.iconFont; pixelSize: 16 }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.toggleTouchpad()
                            }
                        }

                        // 3. Fan Status Card (RPM display for Dual Fans)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 60
                            radius: 14
                            color: "#1c1c1e"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12; anchors.rightMargin: 12
                                spacing: 10

                                Text {
                                    text: String.fromCodePoint(0xF0210) // nf-md-fan
                                    color: (win.fan1Rpm > 0 || win.fan2Rpm > 0) ? Style.green : Style.dim
                                    font { family: Style.iconFont; pixelSize: 18 }
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Layout.alignment: Qt.AlignVCenter
                                    Text {
                                        text: "Fans (Dual)"
                                        color: Style.dim
                                        font { family: Style.font; pixelSize: 10; weight: Font.Medium }
                                    }
                                    Text {
                                        text: (win.fan1Rpm === 0 && win.fan2Rpm === 0) ? "0 RPM (Silent)" : (win.fan1Rpm + " / " + win.fan2Rpm + " RPM")
                                        color: Style.text
                                        font { family: Style.font; pixelSize: 12; weight: Font.DemiBold }
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }
        }
    }
}
