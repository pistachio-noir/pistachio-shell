import qs
import qs.components
import qs.services
import Quickshell
import QtQuick

// Bell with an unread dot, time and date. Opens the notification centre.
Chip {
    id: chip

    leftPadding: 14
    spacing: 10
    Accessible.name: (Notifs.dnd ? "Do not disturb is on. " : "Notifications. ") + Qt.formatDateTime(clock.date, "hh:mm, dddd d MMMM")
    // the full date, and what's waiting in the centre
    tooltip: {
        const fresh = Notifs.notifications.filter(n => Notifs.received(n) > Notifs.seenAt).length;
        return [[Qt.formatDate(clock.date, "dddd d MMMM yyyy")], Notifs.dnd ? ["Do not disturb", Notifs.inDndSchedule ? `until ${NightLight.timeText(Notifs.dndTo)}` : "on"] : ["Notifications", fresh ? `${fresh} new` : "nothing new"]];
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Item {
        anchors.verticalCenter: parent.verticalCenter
        width: 18
        height: 18

        Icon {
            color: Notifs.dnd ? Theme.subtext : chip.foreground
            paths: Notifs.dnd ? Icons.bellOff : Icons.bell
        }

        // 9 px dot with a 2 px ring in the chip's colour, so it reads as cut out of the bell
        Rectangle {
            visible: Notifs.unread
            x: 10
            y: -5
            width: 13
            height: 13
            radius: 6.5
            color: Theme.pistachio
            border.width: 2
            border.color: chip.color
        }
    }

    Column {
        anchors.verticalCenter: parent.verticalCenter

        Text {
            text: Qt.formatDateTime(clock.date, "hh:mm")
            color: Theme.textBright
            font.family: Theme.fontUi
            font.pixelSize: 14
            font.weight: Font.ExtraBold
            font.features: { "tnum": 1 }
            lineHeight: 17
            lineHeightMode: Text.FixedHeight
        }

        Text {
            text: Qt.formatDateTime(clock.date, "ddd d MMM")
            color: Theme.subtext
            font.family: Theme.fontUi
            font.pixelSize: 11
            font.weight: Font.DemiBold
            lineHeight: 14
            lineHeightMode: Text.FixedHeight
        }
    }
}
