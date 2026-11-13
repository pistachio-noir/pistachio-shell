import qs
import qs.components
import qs.services
import QtQuick

// The weather above the calendar and the notification centre (calendar-weather-notifications and
// weather-details-expanded boards; owner's design): now, the city with today's high and low, and the
// next five days; the chevron opens the next hours, with their chance of rain, and four details.
PanelFrame {
    id: root

    property bool expanded
    property real opened: expanded ? 1 : 0
    // its height with the details open, so the window can keep room for them
    readonly property real fullHeight: Theme.tui ? 458 : view.item?.fullHeight ?? 0

    function iconOf(code: int, day: bool): list<string> {
        return WeatherLook.iconOf(code, day);
    }

    function colourOf(code: int, day: bool): color {
        return WeatherLook.colourOf(code, day);
    }

    title: Theme.tui ? "weather" : ""
    detail: Theme.tui ? "now" : ""
    active: false
    height: Theme.tui ? (expanded ? 458 : 170) : view.item?.implicitHeight ?? 0
    radius: Theme.tui ? 0 : Theme.panelRadius
    color: Theme.tui ? Theme.tuiSurface : Theme.surface
    border.width: 1
    border.color: Theme.overlay2
    clip: !Theme.tui
    Accessible.role: Accessible.Grouping
    Accessible.name: Weather.now ? `Weather in ${Weather.place?.name ?? Weather.city}: ${Weather.now.temp} degrees, ${Weather.describe(Weather.now.code).text}` : "Weather"

    Behavior on opened {
        enabled: !Theme.tui
        NumberAnimation {
            duration: Theme.motionDuration
            easing.type: Theme.easing
        }
    }

    Loader { id: view; anchors.fill: parent; sourceComponent: Theme.tui ? tuiView : classicView }
    Component { id: tuiView; TuiWeather { controller: root } }
    Component { id: classicView; Item {
        readonly property real fullHeight: 20 + head.height + 14 + details.height + 20
        implicitHeight: 20 + head.height + 20 + (14 + details.height) * root.opened
    // now and the next five days
    Item {
        id: head

        x: 20
        y: 20
        width: parent.width - 40
        height: 52

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 52
                height: 52
                radius: 26
                color: Theme.overlay

                Icon {
                    anchors.centerIn: parent
                    size: 26
                    paths: Weather.now ? root.iconOf(Weather.now.code, Weather.now.day) : Icons.cloud
                    color: Weather.now ? root.colourOf(Weather.now.code, Weather.now.day) : Theme.subtext
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Weather.now ? `${Weather.now.temp}°` : ""
                color: Theme.textBright
                font.family: Theme.fontUi
                font.pixelSize: 40
                font.weight: Font.ExtraBold
                font.letterSpacing: -0.8
                font.features: { "tnum": 1 }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Text {
                    text: Weather.now ? Weather.describe(Weather.now.code).text : ""
                    color: Theme.textBright
                    font.family: Theme.fontUi
                    font.pixelSize: 14
                    font.weight: Font.ExtraBold
                }

                Text {
                    // (no city in showoff mode: it says where the owner lives)
                    text: !Weather.today ? "" : Showoff.active ? `H ${Weather.today.max}° · L ${Weather.today.min}°` : `${Weather.place?.name ?? Weather.city} · H ${Weather.today.max}° · L ${Weather.today.min}°`
                    color: Theme.subtext
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 20 + forecast.width
                height: forecast.height

                Rectangle {
                    width: 1
                    height: parent.height
                    color: Theme.overlay
                }

                Row {
                    id: forecast

                    x: 20
                    spacing: 4

                    Repeater {
                        model: Weather.days

                        Column {
                            required property var modelData

                            width: 52
                            spacing: 6

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: parent.modelData.name
                                color: Theme.subtext
                                font.family: Theme.fontUi
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                font.letterSpacing: 0.66
                            }

                            Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                size: 20
                                paths: root.iconOf(parent.modelData.code, true)
                                color: root.colourOf(parent.modelData.code, true)
                            }

                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 5

                                Text {
                                    id: high
                                    text: `${parent.parent.modelData.max}°`
                                    color: Theme.textBright
                                    font.family: Theme.fontUi
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                    font.features: { "tnum": 1 }
                                }

                                Text {
                                    anchors.baseline: high.baseline
                                    text: `${parent.parent.modelData.min}°`
                                    color: Theme.subtext
                                    font.family: Theme.fontUi
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    font.features: { "tnum": 1 }
                                }
                            }
                        }
                    }
                }
            }

            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: root.expanded ? Icons.chevronUp : Icons.chevronDown
                Accessible.name: root.expanded ? "Hide weather details" : "Show weather details"
                onClicked: root.expanded = !root.expanded
            }
        }
    }

    // the next hours and the details, under a line
    Column {
        id: details

        x: 20
        y: head.y + head.height + 14
        width: parent.width - 40
        spacing: 14
        opacity: root.opened

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.overlay
        }

        Row {
            width: parent.width
            spacing: (width - 8 * 76) / 7

            Repeater {
                model: Weather.hours

                Rectangle {
                    id: hour

                    required property var modelData
                    required property int index

                    width: 76
                    height: hourColumn.implicitHeight + 20
                    radius: Theme.tileRadius
                    color: index === 0 ? Theme.overlay : "transparent"

                    Column {
                        id: hourColumn

                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: hour.modelData.label
                            color: hour.index === 0 ? Theme.textBright : Theme.subtext
                            font.family: Theme.fontUi
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            font.letterSpacing: 0.44
                            font.features: { "tnum": 1 }
                        }

                        Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            size: 20
                            paths: root.iconOf(hour.modelData.code, hour.modelData.day)
                            color: root.colourOf(hour.modelData.code, hour.modelData.day)
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: `${hour.modelData.temp}°`
                            color: Theme.textBright
                            font.family: Theme.fontUi
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            font.features: { "tnum": 1 }
                        }

                        // the chance of rain, from 10 %
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            height: 14
                            text: hour.modelData.rain >= 10 ? `${hour.modelData.rain}%` : ""
                            color: Theme.sageBlue
                            font.family: Theme.fontUi
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            font.features: { "tnum": 1 }
                        }
                    }
                }
            }
        }

        Row {
            width: parent.width
            spacing: 10

            Repeater {
                model: Weather.now && Weather.today ? [
                    [Icons.thermometer, "Feels like", `${Weather.now.feels}°`],
                    [Icons.wind, "Wind", `${Weather.now.wind} km/h`],
                    [Icons.droplet, "Humidity", `${Weather.now.humidity} %`],
                    [Icons.sunset, "Sunset", Weather.today.sunset]
                ] : []

                Rectangle {
                    id: chip

                    required property var modelData

                    width: (parent.width - 3 * 10) / 4
                    height: 48
                    radius: Theme.tileRadius
                    color: Theme.overlay

                    Row {
                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            size: 16
                            paths: chip.modelData[0]
                            color: Theme.subtext
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            Text {
                                text: chip.modelData[1]
                                color: Theme.subtext
                                font.family: Theme.fontUi
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }

                            Text {
                                text: chip.modelData[2]
                                color: Theme.textBright
                                font.family: Theme.fontUi
                                font.pixelSize: 13
                                font.weight: Font.Bold
                                font.features: { "tnum": 1 }
                            }
                        }
                    }
                }
            }
        }
    }    } }
}
