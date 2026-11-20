import qs
import qs.popups
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtTest

// tests/ambient-clock.test.py's fixture: the real Ambient service and AmbientClock layer with stand-in
// Store, Compositor, FocusMode, Clocks and Media. Idle is set by hand (Ambient.idle's binding replaced).
ShellRoot {
    id: root
    AmbientClock { id: ambient }
    TestCase { id: input; when: false }
    function check(ok, why) { if (!ok) throw Error(why); }
    function find(item, name) { if (item.objectName === name) return item; for (const c of item.children ?? []) { const hit = find(c, name); if (hit) return hit; } return null; }
    function run() {
        const veil = find(ambient.contentItem, "ambient-veil");
        check(!Ambient.shown && !ambient.visible, "off by default");
        Ambient.idle = true;
        input.wait(50);
        check(!Ambient.shown, "idle but switched off: nothing");
        Store.saved.ambientClock = true;
        // in the middle from the start (it glided in from the top-left corner: owner's report, 20 November 2026)
        input.wait(150);
        const group = find(veil, "ambient-group");
        const off = Math.max(Math.abs(group.x + group.width / 2 - veil.width / 2), Math.abs(group.y + group.height / 2 - veil.height / 2));
        check(veil.width > 0 && off <= 40, `centred as it fades in (${Math.round(off)} px off, window ${veil.width}×${veil.height})`);
        input.tryVerify(() => veil.opacity === 1, Theme.dimDuration + 2000);
        check(Ambient.shown && ambient.visible && veil.opacity === 1, `idle on an empty desktop: shown (${Ambient.shown} ${ambient.visible} ${veil.opacity} ${Ambient.enabled} ${Ambient.idle} ${Ambient.desktopEmpty})`);
        check(ambient.mask.width === 0 && ambient.mask.height === 0, "takes no pointer input");
        check(ambient.WlrLayershell.keyboardFocus === WlrKeyboardFocus.None, "takes no keyboard");
        check(find(veil, "ambient-media").visible, "what's playing shows");
        check(find(veil, "ambient-timer").text === "Work 2/4 · 12:30 left", "the Pomodoro line: " + find(veil, "ambient-timer").text);
        // any input ends the idle: out at once
        Ambient.idle = false;
        const t0 = Date.now();
        input.tryVerify(() => !ambient.visible, 3000);
        check(!Ambient.shown && Date.now() - t0 < Theme.motionDuration + 400, `input brings the desktop back at once (${Date.now() - t0} ms)`);
        // a window (floating too) on the workspace keeps it away
        Compositor.windows = [{ workspace: 1, floating: true, hidden: false, minimized: false }];
        Ambient.idle = true;
        input.wait(100);
        check(!Ambient.shown, "not over a window");
        Compositor.windows = [];
        Ambient.idle = false;
        // the delay: 2, 3 or 5 minutes, others refused
        Ambient.setDelay(5); check(Ambient.delay === 5, "delay 5");
        Ambient.setDelay(7); check(Ambient.delay === 5, "7 refused");
        // Preview: shown for previewLength whatever the idle state
        Ambient.previewLength = 400;
        Ambient.preview();
        input.wait(100);
        check(Ambient.shown, "preview shows it");
        input.wait(600);
        check(!Ambient.shown, "preview ends by itself");
        // TUI
        Theme.tui = true;
        input.wait(30);
        check(find(veil, "ambient-time").font.family === Theme.fontTui, "TUI clock in JetBrains Mono");
        Theme.tui = false;
        return "PASS idle/switch/empty-desktop rule, no input taken, media and timer lines, delay, preview, TUI";
    }
    IpcHandler {
        target: "ambientTest"
        function ready(): bool { return Quickshell.screens.length > 0; }
        function run(): string { try { return root.run(); } catch (e) { return "FAIL " + e.message; } }
    }
}
