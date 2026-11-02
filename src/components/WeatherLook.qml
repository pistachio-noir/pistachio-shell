pragma Singleton

import qs
import qs.services
import Quickshell
import QtQuick

// The weather's icon and tint for a WMO code, as on the weather boards: the sun gold, rain sage blue,
// clouds and the night quiet. The weather panel and the lock screen use it.
Singleton {
    function iconOf(code: int, day: bool): list<string> {
        const kind = Weather.describe(code).kind;
        return kind === "clear" ? (day ? Icons.sun : Icons.moon)
            : kind === "partly" ? (day ? Icons.cloudSun : Icons.cloudMoon)
            : kind === "cloud" ? Icons.cloud
            : kind === "fog" ? Icons.cloudFog
            : kind === "drizzle" ? Icons.cloudDrizzle
            : kind === "rain" ? Icons.cloudRain
            : kind === "snow" ? Icons.cloudSnow
            : Icons.cloudLightning;
    }

    function colourOf(code: int, day: bool): color {
        const kind = Weather.describe(code).kind;
        return (kind === "clear" || kind === "partly") && day ? Theme.gold
            : kind === "drizzle" || kind === "rain" ? Theme.sageBlue
            : kind === "snow" ? Theme.text
            : kind === "storm" ? Theme.lavender
            : Theme.subtext;
    }
}
