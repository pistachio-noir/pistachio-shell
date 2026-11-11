pragma Singleton

import Quickshell
import QtQuick

// The weather (owner's request, after phase 8; boards calendar-weather-notifications and
// weather-details-expanded), from Open-Meteo: free, no account. The city is found once by name (its
// geocoding) and only its coordinates are sent, every 30 minutes. Offline it keeps the last reading;
// with none yet, `available` stays false and the panel stays away. °C and km/h.
Singleton {
    id: root

    readonly property string city: Store.saved.weatherCity || "Warsaw" // the board's city, until one is set (the owner's: Kłobuck)
    property var place: null // { name, country, latitude, longitude }
    // "Kłobuck, Poland", for the launcher's setting; the name asked for until it's found
    readonly property string placeName: place ? [place.name, place.country].filter(x => x).join(", ") : city
    property var now: null // { temp, feels, humidity, wind, code, day }
    property var today: null // { max, min, sunset }
    property var days: [] // the next five: { name, code, max, min }
    property var hours: [] // now and the next seven: { label, code, day, temp, rain }
    readonly property bool enabled: ShellSettings.integration("weather") // Settings → Integrations
    readonly property bool available: enabled && now !== null
    onEnabledChanged: if (enabled) refresh()

    function setCity(name: string) {
        Store.saved.weatherCity = name;
    }

    // WMO weather code -> its words and one of: clear, partly, cloud, fog, drizzle, rain, snow, storm
    function describe(code: int): var {
        return code === 0 ? { text: "Clear", kind: "clear" }
            : code === 1 ? { text: "Mainly clear", kind: "partly" }
            : code === 2 ? { text: "Partly cloudy", kind: "partly" }
            : code === 3 ? { text: "Overcast", kind: "cloud" }
            : code <= 48 ? { text: "Fog", kind: "fog" }
            : code <= 57 ? { text: "Drizzle", kind: "drizzle" }
            : code <= 67 ? { text: "Rain", kind: "rain" }
            : code <= 77 ? { text: "Snow", kind: "snow" }
            : code <= 82 ? { text: "Showers", kind: "rain" }
            : code <= 86 ? { text: "Snow showers", kind: "snow" }
            : { text: "Thunderstorm", kind: "storm" };
    }

    // then(answer), or failed() without one (offline, an error, an unreadable answer)
    function get(url: string, then, failed) {
        const request = new XMLHttpRequest();
        request.onreadystatechange = () => {
            if (request.readyState !== XMLHttpRequest.DONE)
                return;
            if (request.status !== 200)
                return failed?.();
            let answer;
            try {
                answer = JSON.parse(request.responseText);
            } catch (e) {
                console.warn("weather: unreadable answer from", url);
                return failed?.();
            }
            then(answer);
        };
        request.open("GET", url);
        request.send();
    }

    // A city by name, through Open-Meteo's geocoding: then(place, problem), with place null and the
    // problem in words when there's none by that name or no answer. The launcher's setting checks a
    // name with it before saving (owner's request, after phase 8).
    function lookup(name: string, then) {
        get(`https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(name)}&count=1&language=en&format=json`, r => {
            const p = r.results?.[0];
            if (p)
                then({ name: p.name, country: p.country ?? "", latitude: p.latitude, longitude: p.longitude }, "");
            else
                then(null, `No place called “${name}”. Check the spelling.`);
        }, () => then(null, "Couldn't reach Open-Meteo. Check the connection."));
    }

    // An answer for a city or place that has changed since it was asked is dropped: the first lookup
    // goes out before Store has read the saved city, and once came back after the saved city's,
    // showing Warsaw instead of Kłobuck (seen 28 October).
    function locate() {
        const asked = city;
        lookup(asked, (p, problem) => {
            if (asked !== city)
                return;
            if (!p)
                return console.warn("weather:", problem);
            place = p;
            refresh();
        });
    }

    function refresh() {
        if (!place)
            return locate();
        const asked = place;
        get(`https://api.open-meteo.com/v1/forecast?latitude=${place.latitude}&longitude=${place.longitude}`
            + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day"
            + "&hourly=temperature_2m,weather_code,precipitation_probability,is_day"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunset&timezone=auto&forecast_days=6", r => {
            if (asked === place)
                read(r);
        });
    }

    function read(r) {
        const c = r.current, h = r.hourly, d = r.daily;
        const round = Math.round;
        // the hour now, as Open-Meteo writes it in local time ("2026-10-28T10:00")
        const first = Math.max(0, h.time.findIndex(t => t.slice(0, 13) === c.time.slice(0, 13)));
        hours = Array.from({ length: 8 }, (_, i) => first + i).filter(i => i < h.time.length).map((i, n) => ({
            label: n === 0 ? "Now" : String(Number(h.time[i].slice(11, 13))),
            code: n === 0 ? c.weather_code : h.weather_code[i],
            day: (n === 0 ? c.is_day : h.is_day[i]) === 1,
            temp: round(n === 0 ? c.temperature_2m : h.temperature_2m[i]),
            rain: h.precipitation_probability[i] ?? 0
        }));
        days = d.time.slice(1, 6).map((t, i) => ({
            name: Qt.formatDate(new Date(`${t}T12:00`), "ddd").toUpperCase(),
            code: d.weather_code[i + 1],
            max: round(d.temperature_2m_max[i + 1]),
            min: round(d.temperature_2m_min[i + 1])
        }));
        today = { max: round(d.temperature_2m_max[0]), min: round(d.temperature_2m_min[0]), sunset: d.sunset[0].slice(11, 16) };
        now = { temp: round(c.temperature_2m), feels: round(c.apparent_temperature), humidity: round(c.relative_humidity_2m), wind: round(c.wind_speed_10m), code: c.weather_code, day: c.is_day === 1 };
    }

    // a new city: look it up again
    onCityChanged: {
        place = null;
        locate();
    }

    Timer {
        running: root.enabled
        interval: 1800000 // 30 min
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
