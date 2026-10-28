import QtQuick

// Apps using the microphone or sharing the screen, for the OSD's privacy cue (owner's request):
// `started` when an app joins (with all the apps now), `stopped` when the last one leaves (with the
// ones that were). A change counts once it has lasted a second, since apps open the mic for a moment
// to look at the devices; the apps already there at startup aren't news.
Item {
    id: root

    property var apps: [] // names; repeats are fine
    property var known: null // as last announced; null until the first look

    signal started(string names)
    signal stopped(string names)

    onAppsChanged: settle.restart()

    function check() {
        const now = apps.filter((a, i) => apps.indexOf(a) === i);
        const was = known;
        known = now;
        if (was === null)
            return;
        if (now.some(a => !was.includes(a)))
            started(now.join(", "));
        else if (now.length === 0 && was.length > 0)
            stopped(was.join(", "));
    }

    Timer {
        id: settle
        running: true
        interval: 1000
        onTriggered: root.check()
    }
}
