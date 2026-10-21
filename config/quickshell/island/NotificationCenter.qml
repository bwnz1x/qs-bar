pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: root

    // List of notification objects: { id, appName, appIcon, image, summary, body, time: Date, rawNotif }
    property var history: []
    property var currentBanner: null
    property bool isBannerActive: false
    property int bannerStage: 0 // 0: "New Notification", 1: summary + body scrolling

    // Grouping helper
    function getGroupedNotifications() {
        const now = new Date()
        const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
        const yesterdayStart = todayStart - (24 * 60 * 60 * 1000)
        const fiveMinAgo = now.getTime() - (5 * 60 * 1000)

        const sections = [
            { title: "Now", items: [] },
            { title: "Today", items: [] },
            { title: "Yesterday", items: [] },
            { title: "Older", items: [] }
        ]

        for (let i = 0; i < history.length; i++) {
            const item = history[i]
            const t = item.time.getTime()
            if (t >= fiveMinAgo) {
                sections[0].items.push(item)
            } else if (t >= todayStart) {
                sections[1].items.push(item)
            } else if (t >= yesterdayStart) {
                sections[2].items.push(item)
            } else {
                sections[3].items.push(item)
            }
        }

        // For each section, group by appName
        const result = []
        for (let s = 0; s < sections.length; s++) {
            const sec = sections[s]
            if (sec.items.length === 0) continue

            const appMap = {}
            for (let j = 0; j < sec.items.length; j++) {
                const notif = sec.items[j]
                const app = notif.appName || "Notification"
                if (!appMap[app]) {
                    appMap[app] = { appName: app, appIcon: notif.image || notif.appIcon, list: [] }
                }
                appMap[app].list.push(notif)
            }
            result.push({ sectionTitle: sec.title, appGroups: Object.values(appMap) })
        }
        return result
    }

    function removeNotification(id) {
        history = history.filter(item => item.id !== id)
    }

    function clearAll() {
        history = []
    }

    function triggerAction(item) {
        if (!item || !item.rawNotif) return
        try {
            if (item.rawNotif.actions && item.rawNotif.actions.length > 0) {
                const def = item.rawNotif.actions.find(a => a.identifier === "default") || item.rawNotif.actions[0]
                if (def && typeof def.invoke === "function") {
                    def.invoke()
                }
            } else if (typeof item.rawNotif.dismiss === "function") {
                item.rawNotif.dismiss()
            }
        } catch (e) {
            console.log("Error invoking notification action:", e)
        }
        removeNotification(item.id)
    }

    NotificationServer {
        id: server
        actionsSupported: true
        imageSupported: true
        bodySupported: true
        persistenceSupported: true

        onNotification: notif => {
            notif.tracked = true
            const entry = {
                id: notif.id || Date.now(),
                appName: notif.appName || "System",
                appIcon: notif.appIcon || "",
                image: notif.image || "",
                summary: notif.summary || "",
                body: notif.body || "",
                time: new Date(),
                rawNotif: notif
            }

            // Prepend to history
            root.history = [entry].concat(root.history.slice(0, 49))

            // Trigger Banner display
            root.currentBanner = entry
            root.bannerStage = 0
            root.isBannerActive = true

            stageTimer.restart()
            bannerDurationTimer.restart()
        }
    }

    // Switch from stage 0 ("New Notification") to stage 1 (scrolling summary/body) after 1.4s
    Timer {
        id: stageTimer
        interval: 1400
        onTriggered: {
            root.bannerStage = 1
        }
    }

    // Total banner duration: 5.5s
    Timer {
        id: bannerDurationTimer
        interval: 5500
        onTriggered: {
            root.isBannerActive = false
            root.bannerStage = 0
        }
    }
}
