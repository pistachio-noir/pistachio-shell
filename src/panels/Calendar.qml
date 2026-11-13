import qs
import qs.components
import qs.services
import Quickshell
import QtQuick
import "calendar.js" as Cal

// Month calendar beside the notification centre (calendar-notifications board): weeks from Monday,
// today as a pistachio chip, ‹ › or the scroll wheel change month, Today goes back. With GNOME
// Calendar's events (owner's request, 11 November 2026; laid out by Claude, no board; Settings →
// Integrations): a dot under a day that has some, and the clicked day's events (today's at first)
// under the grid, read-only; a click on one opens GNOME Calendar. The list keeps one height so the
// window doesn't resize as events arrive.
PanelFrame {
    id: root

    property int year
    property int month // 0–11
    readonly property real cell: (width - 40) / 7
    // A month change slides: the title and the grid have two copies each (MonthPage.qml) that
    // take turns, the one given the new month coming in from `heading` as the other leaves.
    property int page // the copy showing year and month
    property var pages: [{ year: 0, month: 0 }, { year: 0, month: 0 }] // the month each copy shows
    property point heading // (1, 0): the next month, coming in from the right; (0, 0): no slide
    property date selected: new Date() // the day whose events show
    readonly property bool selectedToday: Cal.sameDay(selected, clock.date)
    readonly property var dayEvents: Events.enabled ? Events.on(selected) : []
    readonly property int eventRows: 4
    readonly property real eventsHeight: Events.enabled ? 14 + 1 + 14 + 18 + 8 + eventRows * 40 : 0

    function selectToday() {
        selected = clock.date;
    }

    // shows a month, coming in from `way`
    function show(y: int, m: int, way: point) {
        if (y === year && m === month)
            return;
        const p = pages.slice();
        p[1 - page] = { year: y, month: m };
        pages = p;
        year = y;
        month = m;
        heading = way;
        Events.load(y, m);
        page = 1 - page;
    }

    // sideways from where it is, or at once (`slide` false) as when the centre opens
    function showToday(slide: bool) {
        const y = clock.date.getFullYear();
        const m = clock.date.getMonth();
        show(y, m, Qt.point(slide ? Math.sign((y - year) * 12 + m - month) : 0, 0));
    }

    // ‹ › and ← → slide sideways; the wheel slides up and down
    function step(by: int, wheel: bool) {
        const m = Cal.shift(year, month, by);
        show(m.year, m.month, wheel ? Qt.point(0, by) : Qt.point(by, 0));
    }

    title: Theme.tui ? "cal" : ""
    detail: Theme.tui ? Qt.formatDate(new Date(), "dddd").toLowerCase() : ""
    implicitWidth: Theme.tui ? 232 : 300
    implicitHeight: view.item?.implicitHeight ?? 0
    radius: Theme.tui ? 0 : Theme.panelRadius
    color: Theme.tui ? Theme.tuiSurface : Theme.surface
    border.width: 1
    border.color: Theme.tuiBorder
    Accessible.role: Accessible.Grouping
    Accessible.name: "Calendar"
    Component.onCompleted: showToday(false)
    Connections {
        target: Events
        function onEnabledChanged() {
            if (Events.enabled)
                Events.load(root.year, root.month);
        }
    }

    // the day changes at midnight
    SystemClock {
        id: clock
        precision: SystemClock.Hours
    }

    Loader { id: view; anchors.fill: parent; sourceComponent: Theme.tui ? tuiView : classicView }
    Component { id: tuiView; TuiCalendar { controller: root } }
    Component { id: classicView; Item {
        implicitHeight: 20 + header.height + 14 + weekdays.height + 8 + grid.height + root.eventsHeight + 14 + footer.height + 20
    Item {
        id: header

        x: 20
        y: 20
        width: parent.width - 40
        height: 44

        Repeater {
            model: 2

            MonthPage {
                id: title

                required property int index

                year: root.pages[index].year
                month: root.pages[index].month
                live: index === root.page
                heading: root.heading
                width: header.width
                height: header.height
                distance: 12

                Text {
                    x: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDate(new Date(title.year, title.month, 1), "MMMM yyyy")
                    color: Theme.textBright
                    font.family: Theme.fontUi
                    font.pixelSize: 17
                    font.weight: Font.ExtraBold
                }
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: -8

            MonthButton {
                icon: Icons.chevronLeft
                Accessible.name: "Previous month"
                onClicked: root.step(-1, false)
            }

            MonthButton {
                icon: Icons.chevronRight
                Accessible.name: "Next month"
                onClicked: root.step(1, false)
            }
        }
    }

    Row {
        id: weekdays

        x: 20
        y: header.y + header.height + 14

        Repeater {
            model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

            Text {
                required property string modelData

                width: root.cell
                horizontalAlignment: Text.AlignHCenter
                text: modelData
                color: Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 0.66
            }
        }
    }

    Item {
        id: grid

        x: 20
        y: weekdays.y + weekdays.height + 8
        width: parent.width - 40
        height: 6 * 36
        clip: true // the leaving and arriving rows stop at its edges
        Accessible.role: Accessible.Table
        Accessible.name: Qt.formatDate(new Date(root.year, root.month, 1), "MMMM yyyy")

        Repeater {
            model: 2

            MonthPage {
                id: sheet

                required property int index
                readonly property var days: Cal.days(sheet.year, sheet.month)

                year: root.pages[index].year
                month: root.pages[index].month
                live: index === root.page
                heading: root.heading
                width: grid.width
                height: grid.height
                distance: 36 // a row, or about a column

                Repeater {
                    model: sheet.days

                    Item {
                        id: day

                        required property var modelData
                        required property int index
                        readonly property bool inMonth: modelData.getMonth() === sheet.month
                        readonly property bool today: Cal.sameDay(modelData, clock.date)
                        readonly property bool chosen: Events.enabled && !today && Cal.sameDay(modelData, root.selected)
                        readonly property bool busy: Events.enabled && (Events.byDay[Events.key(modelData)]?.length ?? 0) > 0

                        x: Math.round(index % 7 * root.cell)
                        y: Math.floor(index / 7) * 36
                        width: Math.round(root.cell)
                        height: 36
                        Accessible.role: Accessible.Cell
                        Accessible.name: Qt.formatDate(modelData, "dddd d MMMM") + (today ? ", today" : "")

                        Rectangle {
                            x: Math.round((parent.width - width) / 2)
                            y: 1
                            width: 34
                            height: 34
                            radius: 17
                            color: day.today ? Theme.pistachio : day.chosen ? Theme.overlay2 : dayMouse.containsMouse && Events.enabled ? Theme.overlay : "transparent"

                            Behavior on color {
                                ColorAnimation {
                                    duration: Theme.hoverDuration
                                    easing.type: Theme.easing
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: day.modelData.getDate()
                                color: day.today ? Theme.bg : day.inMonth ? Theme.text : Theme.subtext
                                font.family: Theme.fontUi
                                font.pixelSize: 13
                                font.weight: day.today ? Font.ExtraBold : day.inMonth ? Font.Bold : Font.Medium
                                font.features: { "tnum": 1 }
                            }

                            // a day with events
                            Rectangle {
                                visible: day.busy
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 27
                                width: 4
                                height: 4
                                radius: 2
                                color: day.today ? Theme.bg : day.inMonth ? Theme.subtext : Theme.muted
                            }
                        }

                        MouseArea {
                            id: dayMouse
                            anchors.fill: parent
                            enabled: Events.enabled
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selected = day.modelData
                        }
                    }
                }
            }
        }

        // a wheel notch per month; a touchpad's small steps add up to one
        MouseArea {
            property real scrolled

            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: wheel => {
                scrolled += wheel.angleDelta.y;
                while (Math.abs(scrolled) >= 120) {
                    root.step(scrolled > 0 ? -1 : 1, true);
                    scrolled -= Math.sign(scrolled) * 120;
                }
            }
        }
    }

    // the chosen day's events, under the grid
    Item {
        id: agenda

        x: 20
        y: grid.y + grid.height + 14
        width: parent.width - 40
        height: root.eventsHeight - 14
        visible: Events.enabled

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.overlay
        }

        Text {
            id: agendaTitle
            x: 4
            y: 15
            width: parent.width - 8
            text: (root.selectedToday ? "Today" : Qt.formatDate(root.selected, "dddd d MMMM")) + (root.dayEvents.length ? ` · ${root.dayEvents.length}` : "")
            color: Theme.subtext
            font.family: Theme.fontUi
            font.pixelSize: 12
            font.weight: Font.Bold
            font.features: { "tnum": 1 }
            elide: Text.ElideRight
        }

        Text {
            x: 4
            y: agendaTitle.y + 18 + 8 + 10
            visible: root.dayEvents.length === 0
            text: "No events"
            color: Theme.subtext
            font.family: Theme.fontUi
            font.pixelSize: 13
            font.weight: Font.Medium
        }

        Column {
            y: agendaTitle.y + 18 + 8
            width: parent.width

            Repeater {
                model: root.dayEvents.length > root.eventRows ? root.dayEvents.slice(0, root.eventRows - 1) : root.dayEvents

                Rectangle {
                    id: event

                    required property var modelData
                    readonly property bool started: !modelData.allDay && !Cal.sameDay(new Date(modelData.start), root.selected)

                    width: parent.width
                    height: 40
                    radius: 20
                    color: eventMouse.containsMouse ? Theme.overlay : "transparent"
                    Accessible.role: Accessible.Button
                    Accessible.name: `${time.text}, ${title.text}. Open in Calendar`

                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.hoverDuration
                            easing.type: Theme.easing
                        }
                    }

                    Rectangle {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 4
                        height: 20
                        radius: 2
                        color: Events.colourFor(event.modelData.calendar)
                    }

                    Text {
                        id: time
                        x: 22
                        anchors.verticalCenter: parent.verticalCenter
                        width: 52
                        text: event.modelData.allDay ? "All day" : event.started ? "Ongoing" : Qt.formatTime(new Date(event.modelData.start), "HH:mm")
                        color: Theme.subtext
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.features: { "tnum": 1 }
                    }

                    Text {
                        id: title
                        x: time.x + time.width + 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - 12
                        text: event.modelData.title || "Untitled event"
                        color: Theme.text
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        elide: Text.ElideRight

                        TipHover {}
                    }

                    MouseArea {
                        id: eventMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Events.open()
                    }
                }
            }

            Text {
                x: 22
                height: 40
                verticalAlignment: Text.AlignVCenter
                visible: root.dayEvents.length > root.eventRows
                text: `+${root.dayEvents.length - root.eventRows + 1} more in Calendar`
                color: Theme.subtext
                font.family: Theme.fontUi
                font.pixelSize: 12
                font.weight: Font.Bold
                font.features: { "tnum": 1 }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Events.open()
                }
            }
        }
    }

    // today, and the way back to it
    Item {
        id: footer

        x: 20
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20
        width: parent.width - 40
        height: 14 + 44

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.overlay
        }

        Text {
            x: 4
            y: 14 + (44 - height) / 2
            text: Qt.formatDate(clock.date, "dddd d MMM")
            color: Theme.textBright
            font.family: Theme.fontUi
            font.pixelSize: 13
            font.weight: Font.Bold
        }

        Rectangle {
            anchors.right: parent.right
            y: 14 + 4
            width: todayLabel.implicitWidth + 32
            height: 36
            radius: 18
            color: todayMouse.containsMouse ? Theme.overlay2 : Theme.overlay
            Accessible.role: Accessible.Button
            Accessible.name: "Jump to today"

            Behavior on color {
                ColorAnimation {
                    duration: Theme.hoverDuration
                    easing.type: Theme.easing
                }
            }

            Text {
                id: todayLabel
                anchors.centerIn: parent
                text: "Today"
                color: Theme.text
                font.family: Theme.fontUi
                font.pixelSize: 13
                font.weight: Font.Bold
            }

            MouseArea {
                id: todayMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.showToday(true);
                    root.selectToday();
                }
            }
        }
    }

    } }

    // ‹ and ›: bare chevrons that get a background on hover, like Clear all
    component MonthButton: Rectangle {
        id: button

        required property list<string> icon

        signal clicked

        width: 44
        height: 44
        radius: 22
        color: mouse.containsMouse ? Theme.overlay : "transparent"
        Accessible.role: Accessible.Button

        Behavior on color {
            ColorAnimation {
                duration: Theme.hoverDuration
                easing.type: Theme.easing
            }
        }

        Icon {
            anchors.centerIn: parent
            paths: button.icon
            color: mouse.containsMouse ? Theme.textBright : Theme.subtext
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }
}
