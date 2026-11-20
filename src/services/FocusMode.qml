pragma Singleton

import qs
import Quickshell
import Quickshell.Io
import QtQuick

// Zen mode, Focus sessions and their Pomodoro timer (owner's request, 11 November 2026; laid out by
// Claude, no boards). From the launcher and Settings → Focus & Zen; no IPC (owner's call).
//
// Zen: no bar, pills or desktop icons, toasts held, and Hyprland's gaps and borders at 0 (runtime
// settings, put back as they were; the config files are never touched). Optionally a Pomodoro.
// Focus: one stretch of minutes, or Pomodoro rounds; toasts held except from the apps you allow
// (during a Pomodoro only while working); optionally Zen for the session.
//
// The state lives in Store, so a live reload or restart carries on where it was: the saved gaps
// put back on the way out, and the session's end time.
Singleton {
    id: root

    readonly property var state: Store.saved.focusState ?? ({}) // { zen, zenByFocus, gaps, session }
    readonly property bool zen: state.zen === true
    // { owner: "focus" | "zen", pomodoro, phase: "work" | "break" | "long", round, endsAt (ms) or
    //   left (ms, while paused), length (ms of the phase) }
    readonly property var session: state.session ?? null
    readonly property bool focusing: session !== null && session.owner === "focus"
    // a Pomodoro of its own (owner's request, 12 November 2026): the rounds and the pill, nothing held
    readonly property bool pomodoring: session !== null && session.owner === "pomodoro"
    readonly property bool paused: session !== null && !session.endsAt
    readonly property bool working: session !== null && session.phase === "work"
    // toasts held: Zen, or a Focus session's work time (the allowed apps still show, but not in Zen)
    readonly property bool quiet: zen || focusing && working
    readonly property var allowed: Store.saved.focusAllowed ?? []
    property real now: Date.now()

    // The phone helper receives only this session's public countdown state and the shell's colours;
    // it sends back the phone's Pause/Skip/End.
    property string phoneUrl
    property string phoneQr
    property string phoneQrError
    property string phoneError
    property bool phoneOpen
    property bool phoneToast
    readonly property int phoneToastDuration: 8000
    property bool phoneReady
    readonly property bool phoneWanted: ShellSettings.phonePreview && session !== null
    property bool phoneRestartRequested
    property bool phoneWasActive
    function showPhone() { if (phoneWanted) { phoneToast = false; phoneOpen = true; } }
    function sendPhone() {
        if (phoneReady && session)
            phoneHelper.write(JSON.stringify({phase: phaseName(), endsAt: session.endsAt || 0,
                left: session.left || 0, paused: paused, length: session.length || 0,
                pomodoro: !!session.pomodoro, working: working,
                bg: Theme.bg.toString(), bgAlt: Theme.bgAlt.toString(), overlay: Theme.overlay.toString(),
                overlay2: Theme.overlay2.toString(), subtext: Theme.subtext.toString(), text: Theme.text.toString(),
                textBright: Theme.textBright.toString(), accent: Theme.pistachio.toString(),
                teal: Theme.teal.toString(), danger: Theme.terracotta.toString()}) + "\n");
    }
    // the phone page's buttons (owner's request, 20 November 2026): the pill's own actions
    function phoneAction(action: string) {
        if (action === "pause") pause();
        else if (action === "skip") skip();
        else if (action === "end") endSession();
        else return;
        sendPhone();
    }
    onPhoneWantedChanged: {
        const active = phoneWanted;
        if (active && !phoneWasActive) {
            phoneError = "";
            if (phoneHelper.running) phoneRestartRequested = true;
            else phoneHelper.running = true;
            phoneToast = true;
            phoneToastTimer.restart();
        }
        if (!active) {
            phoneRestartRequested = false;
            phoneHelper.running = false;
            phoneOpen = false;
            phoneToast = false;
            phoneUrl = "";
            phoneQr = "";
            phoneQrError = "";
            phoneReady = false;
        }
        phoneWasActive = active;
        sendPhone();
    }
    Timer { id: phoneToastTimer; interval: root.phoneToastDuration; onTriggered: root.phoneToast = false }
    Process {
        id: phoneHelper
        command: [Quickshell.env("HOME") + "/.local/bin/psc", "phone-timer"]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                if (!root.phoneWanted || root.phoneRestartRequested) return;
                try {
                    const data = JSON.parse(line);
                    if (data.action !== undefined) {
                        root.phoneAction(data.action);
                        return;
                    }
                    root.phoneError = data.error ?? "";
                    root.phoneUrl = data.url ?? "";
                    root.phoneQr = data.qr ?? "";
                    root.phoneQrError = data.qrError ?? "";
                    root.phoneReady = !!data.url;
                    root.sendPhone();
                } catch (e) { root.phoneError = "Could not read the phone server response."; }
            }
        }
        stderr: SplitParser { onRead: line => console.warn("phone timer:", line) }
        onExited: {
            root.phoneReady = false;
            root.phoneUrl = "";
            root.phoneQr = "";
            if (root.phoneWanted && root.phoneRestartRequested) {
                root.phoneRestartRequested = false;
                Qt.callLater(() => { if (root.phoneWanted && !phoneHelper.running) phoneHelper.running = true; });
            } else if (root.phoneWanted && !root.phoneError) root.phoneError = "Phone server stopped.";
        }
    }

    signal announce(string title, string detail, bool on) // for the OSD
    signal phaseFinished(string message)

    function allows(app: string): bool {
        return !zen && allowed.includes(app);
    }

    function minutes(name: string): int {
        return Math.max(1, Store.saved[name] ?? 25);
    }

    function left(): real {
        if (!session)
            return 0;
        return session.endsAt ? Math.max(0, session.endsAt - now) : session.left ?? 0;
    }

    // "18:42", or "1:05:00" past an hour
    function clock(ms: real): string {
        const s = Math.ceil(ms / 1000);
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), sec = s % 60;
        const two = n => String(n).padStart(2, "0");
        return h ? `${h}:${two(m)}:${two(sec)}` : `${m}:${two(sec)}`;
    }

    // "Work 2/4", "Break", "Long break", or "Focus" for a single stretch
    function phaseName(): string {
        if (!session)
            return "";
        if (!session.pomodoro)
            return "Focus";
        return session.phase === "work" ? `Work ${session.round}/${Math.max(1, Store.saved.pomodoroRounds ?? 4)}` : session.phase === "long" ? "Long break" : "Break";
    }

    // Settings → Focus & Zen writes its options here (by name, these only)
    readonly property var options: ["zenPomodoro", "focusPomodoro", "focusMinutes", "focusZen", "pomodoroWork", "pomodoroBreak", "pomodoroLongBreak", "pomodoroRounds"]

    function setOption(name: string, value) {
        if (options.includes(name))
            Store.saved[name] = value;
    }

    function setAllowed(app: string, on: bool) {
        const list = allowed.filter(a => a !== app);
        if (on)
            list.push(app);
        Store.saved.focusAllowed = list;
    }

    function save(changes) {
        Store.saved.focusState = Object.assign({}, state, changes);
    }

    // Zen

    function toggleZen() {
        if (zen)
            stopZen();
        else
            startZen(false);
    }

    function startZen(byFocus: bool) {
        if (zen)
            return;
        save({ zen: true, zenByFocus: byFocus });
        Compositor.zenLayout(true);
        announce("Zen on", Store.saved.zenPomodoro && !byFocus ? "Pomodoro started · toasts wait" : "Toasts wait until you leave", true);
        if (!byFocus && Store.saved.zenPomodoro && !session)
            begin("zen", true);
    }

    function stopZen() {
        if (!zen)
            return;
        const ending = session?.owner === "zen";
        save({ zen: false, zenByFocus: false, session: ending ? null : session });
        Compositor.zenLayout(false);
        announce("Zen off", ending ? "Pomodoro ended" : "Back to your desktop", false);
    }

    // Focus

    function startFocus() {
        if (session?.owner === "focus")
            return;
        if (session)
            save({ session: null });
        begin("focus", Store.saved.focusPomodoro === true);
        if (Store.saved.focusZen && !zen)
            startZen(true);
        announce("Focus on", Store.saved.focusPomodoro ? `Pomodoro · ${minutes("pomodoroWork")} min of work` : `${minutes("focusMinutes")} min · toasts wait`, true);
    }

    function endSession() {
        if (!session)
            return;
        const owner = session.owner;
        save({ session: null });
        if (owner === "zen")
            announce("Pomodoro ended", "Zen stays on", false);
        else if (owner === "pomodoro")
            announce("Pomodoro ended", "", false);
        else {
            if (state.zenByFocus)
                stopZen();
            announce("Focus ended", "Toasts are back", false);
        }
    }

    function togglePomodoro() {
        if (pomodoring) {
            endSession();
            return;
        }
        if (session)
            save({ session: null });
        begin("pomodoro", true);
        announce("Pomodoro", `${minutes("pomodoroWork")} min of work, then ${minutes("pomodoroBreak")} min off`, true);
    }

    function toggleFocus() {
        if (focusing)
            endSession();
        else
            startFocus();
    }

    function begin(owner: string, pomodoro: bool) {
        const length = 60000 * (pomodoro ? minutes("pomodoroWork") : minutes("focusMinutes"));
        now = Date.now();
        save({ session: { owner: owner, pomodoro: pomodoro, phase: "work", round: 1, endsAt: now + length, length: length } });
    }

    function pause() {
        if (!session)
            return;
        now = Date.now();
        if (session.endsAt)
            save({ session: Object.assign({}, session, { endsAt: 0, left: Math.max(0, session.endsAt - now) }) });
        else
            save({ session: Object.assign({}, session, { endsAt: now + (session.left ?? 0), left: 0 }) });
    }

    // on to the next phase now (a Pomodoro), or the end (a single stretch)
    function skip() {
        advance(false);
    }

    function advance(onTime: bool) {
        if (!session)
            return;
        Quickshell.execDetached(["pw-play", Quickshell.shellPath("sounds/notification.wav")]);
        if (!session.pomodoro) {
            if (onTime) phaseFinished("Focus complete!");
            const owner = session.owner;
            save({ session: null });
            if (state.zenByFocus)
                stopZen();
            announce(onTime ? "Focus done" : "Focus ended", onTime ? `${minutes("focusMinutes")} min well spent` : "Toasts are back", false);
            return;
        }
        const rounds = Math.max(1, Store.saved.pomodoroRounds ?? 4);
        let phase, round = session.round;
        if (session.phase === "work")
            phase = round % rounds === 0 ? "long" : "break";
        else {
            phase = "work";
            round = session.phase === "long" ? 1 : round + 1;
        }
        if (onTime) phaseFinished(phase === "work" ? "Back to work!" : "Break time!");
        const length = 60000 * (phase === "work" ? minutes("pomodoroWork") : phase === "long" ? minutes("pomodoroLongBreak") : minutes("pomodoroBreak"));
        now = Date.now();
        save({ session: Object.assign({}, session, { phase: phase, round: round, endsAt: now + length, left: 0, length: length }) });
        announce(phase === "work" ? `Work ${round}/${rounds}` : phase === "long" ? "Long break" : "Break", phase === "work" ? `${minutes("pomodoroWork")} min · toasts wait` : `${Math.round(length / 60000)} min · stretch your legs`, phase === "work");
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.session !== null
        triggeredOnStart: true
        onTriggered: {
            root.now = Date.now();
            root.sendPhone();
            if (root.session?.endsAt && root.now >= root.session.endsAt)
                root.advance(true);
        }
    }

    // after a restart, Zen's layout again (Hyprland forgets runtime settings on a config reload too:
    // Compositor reapplies it then)
    Component.onCompleted: {
        if (zen) Compositor.zenLayout(true);
        if (phoneWanted && !phoneHelper.running) phoneHelper.running = true;
    }
}
