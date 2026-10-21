import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire

PanelWindow {
    id: win
    required property var modelData
    screen: modelData

    anchors { top: true; left: true; right: true }
    implicitHeight: 380                       // room for the expanded island (player / dash / notifications)
    exclusiveZone: Style.compactH + Style.gap * 2
    color: "transparent"
    WlrLayershell.namespace: "dynamic-island"
    WlrLayershell.layer: WlrLayer.Top

    // only the island itself takes input; the rest of the strip is click-through
    mask: Region { item: island }

    // ───────────────────────── data ─────────────────────────

    SystemClock { id: clock; precision: SystemClock.Seconds }

    readonly property MprisPlayer player: {
        const ps = Mpris.players.values
        return ps.find(p => p.isPlaying) ?? ps[0] ?? null
    }
    readonly property bool playing: player?.isPlaying ?? false
    readonly property real trackLen: player?.length ?? 0
    readonly property bool hasLen: trackLen > 0 && trackLen < 43200

    readonly property PwNode sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: [win.sink] }
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false

    // screen brightness: reads whichever backlight device (intel_backlight, nvidia_0, etc.) is active
    property real brightness: 0           // 0..1
    Process {
        id: blProc
        command: ["sh", "-c", "for d in /sys/class/backlight/*; do [ -d \"$d\" ] || continue; c=$(cat \"$d/brightness\" 2>/dev/null || echo 0); m=$(cat \"$d/max_brightness\" 2>/dev/null || echo 1); if [ \"$c\" -gt 0 ]; then awk -v c=\"$c\" -v m=\"$m\" 'BEGIN { print c / m }'; exit; fi; done; for d in /sys/class/backlight/*; do [ -d \"$d\" ] || continue; c=$(cat \"$d/brightness\" 2>/dev/null || echo 0); m=$(cat \"$d/max_brightness\" 2>/dev/null || echo 1); awk -v c=\"$c\" -v m=\"$m\" 'BEGIN { print c / m }'; exit; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const val = parseFloat(text.trim())
                if (!isNaN(val)) {
                    const clamped = Math.max(0, Math.min(1, val))
                    if (Math.abs(clamped - win.brightness) > 0.005) {
                        win.brightness = clamped
                        win.showOsd("brightness")
                    }
                }
            }
        }
    }
    Timer {
        interval: 180; repeat: true; running: true; triggeredOnStart: true
        onTriggered: if (!blProc.running) blProc.running = true
    }

    readonly property int wsId: Hyprland.focusedWorkspace?.id ?? 1
    readonly property var wsList: {
        let top = 5
        for (const w of Hyprland.workspaces.values)
            if (w.id > top && w.id <= 10) top = w.id
        const out = []
        for (let i = 1; i <= top; i++) out.push(i)
        return out
    }
    function wsOccupied(id) {
        return Hyprland.workspaces.values.some(w => w.id === id && (w.toplevels?.values?.length ?? 1) > 0)
    }

    // accent colour pulled from the album art (falls back to white)
    ColorQuantizer {
        id: quant
        source: win.player?.trackArtUrl ?? ""
        depth: 3
        rescaleSize: 48
    }
    readonly property color accent: {
        let best = null, score = -1
        const cs = quant.colors
        for (let i = 0; i < cs.length; i++) {
            const c = cs[i]
            const s = c.hsvSaturation * c.hsvValue
            if (c.hsvValue > 0.3 && s > score) { score = s; best = c }
        }
        if (!best || best.hsvSaturation < 0.15) return "#ffffff"
        return Qt.hsva(best.hsvHue, Math.min(best.hsvSaturation, 0.75), Math.max(best.hsvValue, 0.9), 1)
    }

    function fmt(s) {
        s = Math.max(0, Math.floor(s))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }
    function volIcon() {
        if (muted || volume <= 0) return String.fromCodePoint(0xF0581)
        return volume < 0.5 ? "\uf027" : "\uf028"
    }

    // ───────────────────────── state ─────────────────────────

    property bool expanded: false
    // expanded menu view: "media", "dash", "notifications"
    property string expandedView: "media"
    property string osd: ""               // "", "volume", "brightness", "workspace"
    property bool ready: false            // ignore change signals during startup

    // When a notification arrives:
    // - on not hover: display "notif" banner mode
    // - if hovered while banner is active: jump directly to "notifications" expanded menu
    readonly property bool hasBanner: NotificationCenter.isBannerActive && NotificationCenter.currentBanner !== null

    readonly property string mode: {
        if (expanded) {
            return expandedView === "notifications" ? "notifications"
                 : (expandedView === "media" && player !== null) ? "player" : "dash"
        }
        if (hasBanner) return "notif"
        if (osd !== "") return osd
        if (player !== null && playing) return "media"
        return "idle"
    }

    readonly property var sizes: ({
        idle:          [200, Style.compactH],
        media:         [300, Style.compactH],
        notif:         [360, Style.compactH],
        workspace:     [250, Style.compactH],
        volume:        [320, 40],
        brightness:    [320, 40],
        player:        [430, 184],
        dash:          [430, 150],
        notifications: [440, 320]
    })

    function cycleExpandedView() {
        if (expandedView === "media") expandedView = "dash"
        else if (expandedView === "dash") expandedView = "notifications"
        else expandedView = (player !== null) ? "media" : "dash"
    }

    function showOsd(kind) {
        if (!ready || expanded) return
        osd = kind
        osdTimer.restart()
    }

    Timer { interval: 1500; running: true; onTriggered: win.ready = true }
    Timer { id: osdTimer; interval: 1600; onTriggered: win.osd = "" }
    Timer { id: expandTimer; interval: 180; onTriggered: win.expanded = true }
    Timer { id: collapseTimer; interval: 350; onTriggered: win.expanded = false }

    // keep the progress bar moving
    Timer {
        interval: 1000; repeat: true
        running: win.playing && win.mode === "player"
        onTriggered: win.player?.positionChanged()
    }

    Connections {
        target: win.sink?.audio ?? null
        function onVolumeChanged() { win.showOsd("volume") }
        function onMutedChanged() { win.showOsd("volume") }
    }
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            if (Hyprland.focusedMonitor?.name === win.screen?.name) win.showOsd("workspace")
        }
    }

    // ───────────────────────── the island ─────────────────────────

    Rectangle {
        id: island
        anchors.horizontalCenter: parent.horizontalCenter
        y: Style.gap
        width: win.sizes[win.mode][0]
        height: win.sizes[win.mode][1]
        radius: Math.min(height / 2, 40)
        color: Style.bg
        clip: true

        // smooth expansion that decelerates to a stop without bouncing
        Behavior on width  { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

        HoverHandler {
            onHoveredChanged: {
                if (hovered) {
                    collapseTimer.stop()
                    // If a notification is actively showing its banner when hovered, open the notification center directly!
                    if (win.hasBanner) {
                        win.expandedView = "notifications"
                    }
                    expandTimer.restart()
                } else {
                    expandTimer.stop()
                    collapseTimer.restart()
                }
            }
        }

        // background click / scroll handling (sits under the content)
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            onClicked: m => {
                if (m.button === Qt.MiddleButton) win.player?.togglePlaying()
                else if (m.button === Qt.RightButton && win.sink) win.sink.audio.muted = !win.muted
                else if (win.expanded) win.cycleExpandedView()   // swap media -> dash -> notifications
            }
            onWheel: w => {
                if (!win.sink?.audio) return
                const step = w.angleDelta.y > 0 ? 0.05 : -0.05
                win.sink.audio.volume = Math.max(0, Math.min(1.5, win.volume + step))
            }
        }

        // ── idle: clock • workspace ──
        View {
            active: win.mode === "idle"
            width: win.sizes.idle[0] - 32
            height: Style.compactH

            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: Qt.formatDateTime(clock.date, "h:mm")
                color: Style.text
                font { family: Style.font; pixelSize: 14; weight: Font.DemiBold }
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 10
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: win.wsId
                    color: Style.dim
                    font { family: Style.font; pixelSize: 13; weight: Font.DemiBold }
                }
            }
        }

        // ── notification banner (on not hover) ──
        View {
            active: win.mode === "notif"
            width: win.sizes.notif[0] - 24
            height: Style.compactH

            RowLayout {
                anchors.fill: parent
                spacing: 10

                // App Icon or default bell
                Item {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    Layout.alignment: Qt.AlignVCenter

                    Image {
                        anchors.fill: parent
                        source: NotificationCenter.currentBanner?.image || NotificationCenter.currentBanner?.appIcon || ""
                        fillMode: Image.PreserveAspectFit
                        visible: status === Image.Ready
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !(NotificationCenter.currentBanner?.image)
                        text: "\uf0f3"
                        color: Style.orange
                        font { family: Style.iconFont; pixelSize: 14 }
                    }
                }

                // Stage 0: Brief "New Notification"
                Item {
                    visible: NotificationCenter.bannerStage === 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    RowLayout {
                        anchors.fill: parent
                        spacing: 6
                        Text {
                            text: "New Notification"
                            color: Style.text
                            font { family: Style.font; pixelSize: 13; weight: Font.DemiBold }
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        Text {
                            text: NotificationCenter.currentBanner?.appName || ""
                            color: Style.dim
                            font { family: Style.font; pixelSize: 11 }
                        }
                    }
                }

                // Stage 1: Scrolled Title / Content
                Item {
                    visible: NotificationCenter.bannerStage === 1
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    Row {
                        id: marqueeRow
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        Text {
                            text: NotificationCenter.currentBanner?.summary || ""
                            color: Style.text
                            font { family: Style.font; pixelSize: 13; weight: Font.DemiBold }
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            visible: (NotificationCenter.currentBanner?.body || "") !== ""
                            text: "·"
                            color: Style.dim
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            visible: (NotificationCenter.currentBanner?.body || "") !== ""
                            text: NotificationCenter.currentBanner?.body || ""
                            color: Style.dim
                            font { family: Style.font; pixelSize: 12 }
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        // Smooth marquee scroll if the text exceeds the container width
                        NumberAnimation on x {
                            running: win.mode === "notif" && NotificationCenter.bannerStage === 1 && marqueeRow.width > (win.sizes.notif[0] - 80)
                            from: 0
                            to: -(marqueeRow.width - (win.sizes.notif[0] - 80) + 10)
                            duration: Math.max(2500, marqueeRow.width * 18)
                            loops: 1
                            easing.type: Easing.Linear
                        }
                    }
                }
            }
        }

        // ── compact media: art • waveform ──
        View {
            active: win.mode === "media"
            width: win.sizes.media[0] - 20
            height: Style.compactH

            ClippingRectangle {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: 24; height: 24; radius: 7
                color: Style.track
                Image {
                    anchors.fill: parent
                    source: win.player?.trackArtUrl ?? ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize { width: 64; height: 64 }
                }
            }
            Text {
                anchors.centerIn: parent
                text: Qt.formatDateTime(clock.date, "h:mm")
                color: Style.text
                font { family: Style.font; pixelSize: 14; weight: Font.DemiBold }
            }
            Waveform {
                anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                playing: win.playing
                color: win.accent
                maxH: 16
            }
        }

        // ── workspace OSD ──
        View {
            active: win.mode === "workspace"
            width: win.sizes.workspace[0] - 36
            height: Style.compactH

            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: "Workspace " + win.wsId
                color: Style.text
                font { family: Style.font; pixelSize: 13; weight: Font.DemiBold }
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 4
                Repeater {
                    model: win.wsList.slice(0, 6)
                    delegate: Rectangle {
                        required property int modelData
                        readonly property bool on: modelData === win.wsId
                        anchors.verticalCenter: parent.verticalCenter
                        width: on ? 14 : 6; height: 6; radius: 3
                        color: on ? Style.text : win.wsOccupied(modelData) ? Style.dim : Style.track
                        Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                    }
                }
            }
        }

        // ── volume OSD ──
        View {
            active: win.mode === "volume"
            width: win.sizes.volume[0] - 36
            height: 40

            RowLayout {
                anchors.fill: parent
                spacing: 12
                Text {
                    Layout.preferredWidth: 20
                    text: win.volIcon()
                    color: win.muted ? Style.dim : Style.text
                    font { family: Style.iconFont; pixelSize: 16 }
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 6; radius: 3
                    color: Style.track
                    Rectangle {
                        height: parent.height; radius: 3
                        width: parent.width * Math.min(1, win.muted ? 0 : win.volume)
                        color: Style.text
                        Behavior on width { NumberAnimation { duration: 120 } }
                    }
                }
                Text {
                    Layout.preferredWidth: 34
                    horizontalAlignment: Text.AlignRight
                    text: win.muted ? "Off" : Math.round(win.volume * 100)
                    color: Style.dim
                    font { family: Style.font; pixelSize: 13; weight: Font.DemiBold }
                }
            }
        }

        // ── brightness OSD ──
        View {
            active: win.mode === "brightness"
            width: win.sizes.brightness[0] - 36
            height: 40

            RowLayout {
                anchors.fill: parent
                spacing: 12
                Text {
                    Layout.preferredWidth: 20
                    horizontalAlignment: Text.AlignHCenter
                    text: "\uf185"
                    color: Style.text
                    font { family: Style.iconFont; pixelSize: 16 }
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 6; radius: 3
                    color: Style.track
                    Rectangle {
                        height: parent.height; radius: 3
                        width: parent.width * win.brightness
                        color: Style.text
                        Behavior on width { NumberAnimation { duration: 120 } }
                    }
                }
                Text {
                    Layout.preferredWidth: 34
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(win.brightness * 100)
                    color: Style.dim
                    font { family: Style.font; pixelSize: 13; weight: Font.DemiBold }
                }
            }
        }

        // ── expanded: now playing ──
        View {
            active: win.mode === "player"
            width: win.sizes.player[0] - 44
            height: win.sizes.player[1] - 36

            ColumnLayout {
                anchors.fill: parent
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    ClippingRectangle {
                        Layout.preferredWidth: 60; Layout.preferredHeight: 60
                        radius: 14
                        color: Style.track
                        Image {
                            anchors.fill: parent
                            source: win.player?.trackArtUrl ?? ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize { width: 160; height: 160 }
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: !(win.player?.trackArtUrl)
                            text: "\uf001"
                            color: Style.dim
                            font { family: Style.iconFont; pixelSize: 22 }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            Layout.fillWidth: true
                            text: win.player?.trackTitle || "Not Playing"
                            elide: Text.ElideRight
                            color: Style.text
                            font { family: Style.font; pixelSize: 15; weight: Font.DemiBold }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: win.player?.trackArtist || win.player?.identity || ""
                            elide: Text.ElideRight
                            color: Style.dim
                            font { family: Style.font; pixelSize: 13 }
                        }
                    }
                    Waveform {
                        Layout.alignment: Qt.AlignVCenter
                        playing: win.playing
                        color: win.accent
                        maxH: 20
                    }
                }

                // progress
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    visible: win.hasLen
                    Text {
                        Layout.preferredWidth: 34
                        text: win.fmt(win.player?.position ?? 0)
                        color: Style.dim
                        font { family: Style.font; pixelSize: 11; weight: Font.Medium }
                    }
                    Item {
                        Layout.fillWidth: true
                        height: 12
                        Rectangle {
                            id: trackBar
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: seek.containsMouse ? 8 : 5
                            radius: height / 2
                            color: Style.track
                            Behavior on height { NumberAnimation { duration: 150 } }
                            Rectangle {
                                height: parent.height; radius: parent.radius
                                width: parent.width * Math.min(1, (win.player?.position ?? 0) / Math.max(1, win.trackLen))
                                color: Style.text
                            }
                        }
                        MouseArea {
                            id: seek
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: win.player?.canSeek ?? false
                            cursorShape: Qt.PointingHandCursor
                            onClicked: m => win.player.position = (m.x / width) * win.trackLen
                        }
                    }
                    Text {
                        Layout.preferredWidth: 38
                        horizontalAlignment: Text.AlignRight
                        text: "-" + win.fmt(win.trackLen - (win.player?.position ?? 0))
                        color: Style.dim
                        font { family: Style.font; pixelSize: 11; weight: Font.Medium }
                    }
                }

                // controls
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 44
                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\uf048"; size: 20
                        onClicked: win.player?.previous()
                    }
                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.playing ? "\uf04c" : "\uf04b"; size: 26
                        onClicked: win.player?.togglePlaying()
                    }
                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\uf051"; size: 20
                        onClicked: win.player?.next()
                    }
                }
            }
        }

        // ── expanded: dashboard (no media) ──
        View {
            active: win.mode === "dash"
            width: win.sizes.dash[0] - 48
            height: win.sizes.dash[1] - 36

            ColumnLayout {
                anchors.fill: parent
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    ColumnLayout {
                        spacing: 0
                        Text {
                            text: Qt.formatDateTime(clock.date, "h:mm")
                            color: Style.text
                            font { family: Style.font; pixelSize: 40; weight: Font.Light }
                        }
                        Text {
                            text: Qt.formatDateTime(clock.date, "dddd, MMMM d")
                            color: Style.dim
                            font { family: Style.font; pixelSize: 13; weight: Font.Medium }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    ColumnLayout {
                        spacing: 8
                        Layout.alignment: Qt.AlignVCenter
                        RowLayout {
                            Layout.alignment: Qt.AlignRight
                            spacing: 8
                            Text {
                                text: win.muted ? "Muted" : Math.round(win.volume * 100) + "%"
                                color: Style.text
                                font { family: Style.font; pixelSize: 13; weight: Font.DemiBold }
                            }
                            IconButton {
                                Layout.preferredWidth: 20
                                text: win.volIcon(); size: 16
                                color: win.muted ? Style.dim : Style.text
                                onClicked: if (win.sink) win.sink.audio.muted = !win.muted
                            }
                        }
                    }
                }

                // workspaces
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 6
                    Repeater {
                        model: win.wsList
                        delegate: Rectangle {
                            id: dot
                            required property int modelData
                            readonly property bool on: modelData === win.wsId
                            width: on ? 34 : 22; height: 22; radius: 11
                            color: on ? Style.text : dotArea.containsMouse ? "#48484a"
                                 : win.wsOccupied(modelData) ? Style.track : "#1c1c1e"
                            Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text {
                                anchors.centerIn: parent
                                text: dot.modelData
                                color: dot.on ? Style.bg : Style.dim
                                font { family: Style.font; pixelSize: 11; weight: Font.DemiBold }
                            }
                            MouseArea {
                                id: dotArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + dot.modelData + " })")
                            }
                        }
                    }
                }
            }
        }

        // ── expanded: notification center ──
        View {
            active: win.mode === "notifications"
            width: win.sizes.notifications[0] - 36
            height: win.sizes.notifications[1] - 32

            ColumnLayout {
                anchors.fill: parent
                spacing: 10

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "Notification Center"
                        color: Style.text
                        font { family: Style.font; pixelSize: 15; weight: Font.DemiBold }
                        Layout.fillWidth: true
                    }

                    Text {
                        visible: NotificationCenter.history.length > 0
                        text: "Clear All"
                        color: Style.dim
                        font { family: Style.font; pixelSize: 11; weight: Font.Medium }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: NotificationCenter.clearAll()
                        }
                    }
                }

                // Empty State
                Item {
                    visible: NotificationCenter.history.length === 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Column {
                        anchors.centerIn: parent
                        spacing: 8
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "\uf0f3"
                            color: Style.dim
                            font { family: Style.iconFont; pixelSize: 28 }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "No New Notifications"
                            color: Style.dim
                            font { family: Style.font; pixelSize: 13 }
                        }
                    }
                }

                // Grouped Notification List
                ListView {
                    visible: NotificationCenter.history.length > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 12
                    model: NotificationCenter.getGroupedNotifications()

                    delegate: Column {
                        id: sectionCol
                        required property var modelData
                        width: ListView.view.width
                        spacing: 6

                        // Section Title: Now / Today / Yesterday / Older
                        Text {
                            text: sectionCol.modelData.sectionTitle
                            color: Style.dim
                            font { family: Style.font; pixelSize: 11; weight: Font.Bold }
                        }

                        // App Groups in this Section
                        Repeater {
                            model: sectionCol.modelData.appGroups
                            delegate: Column {
                                id: appGroupCol
                                required property var modelData
                                width: sectionCol.width
                                spacing: 4

                                // App Header
                                Row {
                                    spacing: 6
                                    Image {
                                        width: 14; height: 14
                                        anchors.verticalCenter: parent.verticalCenter
                                        source: appGroupCol.modelData.appIcon || ""
                                        visible: status === Image.Ready
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: appGroupCol.modelData.appName
                                        color: Style.dim
                                        font { family: Style.font; pixelSize: 11; weight: Font.DemiBold }
                                    }
                                }

                                // List of notifications for this app
                                Repeater {
                                    model: appGroupCol.modelData.list
                                    delegate: Rectangle {
                                        id: notifCard
                                        required property var modelData
                                        width: appGroupCol.width
                                        height: notifCardCol.implicitHeight + 16
                                        radius: 12
                                        color: notifMa.containsMouse ? "#242426" : "#1c1c1e"

                                        ColumnLayout {
                                            id: notifCardCol
                                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                                            spacing: 2

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text {
                                                    text: notifCard.modelData.summary || "Notification"
                                                    color: Style.text
                                                    font { family: Style.font; pixelSize: 12; weight: Font.DemiBold }
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    text: Qt.formatDateTime(notifCard.modelData.time, "h:mm ap")
                                                    color: Style.dim
                                                    font { family: Style.font; pixelSize: 10 }
                                                }
                                            }

                                            Text {
                                                visible: (notifCard.modelData.body || "") !== ""
                                                text: notifCard.modelData.body
                                                color: Style.dim
                                                font { family: Style.font; pixelSize: 11 }
                                                Layout.fillWidth: true
                                                wrapMode: Text.Wrap
                                                maximumLineCount: 2
                                                elide: Text.ElideRight
                                            }
                                        }

                                        MouseArea {
                                            id: notifMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: NotificationCenter.triggerAction(notifCard.modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
