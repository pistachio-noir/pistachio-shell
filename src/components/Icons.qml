pragma Singleton

import Quickshell
import QtQuick

// Lucide path data from the design boards, for Icon.paths. Every path starts with an absolute "M".
Singleton {
    readonly property list<string> slash: ["M2 2l20 20"]

    readonly property list<string> bell: ["M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9", "M10.3 21a1.94 1.94 0 0 0 3.4 0"]
    readonly property list<string> bellOff: ["M8.7 3A6 6 0 0 1 18 8a21.3 21.3 0 0 0 .6 5", "M17 17H3s3-2 3-9a4.67 4.67 0 0 1 .3-1.7", "M10.3 21a1.94 1.94 0 0 0 3.4 0", "M2 2l20 20"]
    readonly property list<string> ethernet: ["M15 20l3-3h2a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h2l3 3z", "M6 8v1", "M10 8v1", "M14 8v1", "M18 8v1"]
    readonly property list<string> layers: ["M12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83Z", "M22 17.65l-9.17 4.16a2 2 0 0 1-1.66 0L2 17.65", "M22 12.65l-9.17 4.16a2 2 0 0 1-1.66 0L2 12.65"]
    readonly property list<string> inbox:["M22 12h-6l-2 3h-4l-2-3H2", "M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"]
    readonly property list<string> bluetooth:["M7 7l10 10-5 5V2l5 5L7 17"]
    readonly property list<string> volume: ["M11 5 6 9H2v6h4l5 4V5z", "M15.54 8.46a5 5 0 0 1 0 7.07", "M19.07 4.93a10 10 0 0 1 0 14.14"]
    readonly property list<string> volumeMuted: ["M11 5 6 9H2v6h4l5 4V5z", "M22 9l-6 6", "M16 9l6 6"]
    readonly property list<string> speaker: ["M4 4a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v16a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z", "M8 14a4 4 0 1 0 8 0a4 4 0 1 0-8 0", "M12 6h.01"]
    readonly property list<string> headphones: ["M3 14h3a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-7a9 9 0 0 1 18 0v7a2 2 0 0 1-2 2h-1a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2h3"]
    readonly property list<string> moon: ["M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"]
    readonly property list<string> sun: ["M8 12a4 4 0 1 0 8 0a4 4 0 1 0-8 0", "M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"]
    readonly property list<string> thermometer: ["M14 4v10.54a4 4 0 1 1-4 0V4a2 2 0 0 1 4 0Z"]
    readonly property list<string> calculator: ["M4 4a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v16a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z", "M8 6h8", "M16 14v4", "M16 10h.01", "M12 10h.01", "M8 10h.01", "M12 14h.01", "M8 14h.01", "M12 18h.01", "M8 18h.01"]
    readonly property list<string> music: ["M9 18V5l12-2v13", "M3 18a3 3 0 1 0 6 0a3 3 0 1 0-6 0", "M15 16a3 3 0 1 0 6 0a3 3 0 1 0-6 0"]
    readonly property list<string> play: ["M6 3l14 9-14 9z"]
    readonly property list<string> pause: ["M14 5a1 1 0 0 1 1-1h2a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1h-2a1 1 0 0 1-1-1z", "M6 5a1 1 0 0 1 1-1h2a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1z"]
    readonly property list<string> skipBack: ["M19 20L9 12l10-8z", "M5 19V5"]
    readonly property list<string> skipForward: ["M5 4l10 8-10 8z", "M19 5v14"]
    readonly property list<string> check: ["M20 6 9 17l-5-5"]
    readonly property list<string> chevronLeft: ["M15 18l-6-6 6-6"]
    readonly property list<string> chevronRight: ["M9 18l6-6-6-6"]
    readonly property list<string> chevronDown: ["M6 9l6 6 6-6"]
    readonly property list<string> chevronUp: ["M18 15l-6-6-6 6"]
    readonly property list<string> shieldAlert: ["M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z", "M12 9v4", "M12 17h.01"]
    readonly property list<string> minus: ["M5 12h14"]
    readonly property list<string> plus: ["M5 12h14", "M12 5v14"]
    readonly property list<string> micOff: ["M2 2l20 20", "M18.89 13.23A7.12 7.12 0 0 0 19 12v-2", "M5 10v2a7 7 0 0 0 12 5", "M15 9.34V5a3 3 0 0 0-5.68-1.33", "M9 9v3a3 3 0 0 0 5.12 2.12", "M12 19v3"]
    readonly property list<string> clock: ["M2 12a10 10 0 1 0 20 0a10 10 0 1 0-20 0", "M12 6v6l4 2"]
    readonly property list<string> power: ["M18.36 6.64a9 9 0 1 1-12.73 0", "M12 2v10"]
    readonly property list<string> close: ["M18 6 6 18", "M6 6l12 12"]
    readonly property list<string> loader: ["M21 12a9 9 0 1 1-6.219-8.56"]
    readonly property list<string> search: ["M3 11a8 8 0 1 0 16 0a8 8 0 1 0-16 0", "M21 21l-4.3-4.3"]
    readonly property list<string> lock: ["M3 13a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z", "M7 11V7a5 5 0 0 1 10 0v4"]
    readonly property list<string> logOut: ["M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4", "M16 17l5-5-5-5", "M21 12H9"]
    readonly property list<string> reboot: ["M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8", "M21 3v5h-5", "M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16", "M8 16H3v5"]
    readonly property list<string> user: ["M8 8a4 4 0 1 0 8 0a4 4 0 1 0-8 0", "M4 21a8 8 0 0 1 16 0"]
    readonly property list<string> window:["M2 6a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2z", "M2 9h20"]
}
