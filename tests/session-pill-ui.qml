import qs
import qs.popups
import qs.services
import Quickshell
import Quickshell.Io
import QtQuick
import QtTest

// tests/session-pill.test.py's fixture: the real SessionPill with a stand-in FocusMode.
ShellRoot {
    id: root
    SessionPill { id: pill }
    TestCase { id: input; parent: pill.contentItem; when: false }
    function check(ok, why) { if (!ok) throw Error(why); }
    function find(item, label) { if (item.label === label) return item; for (const c of item.children ?? []) { const hit = find(c, label); if (hit) return hit; } return null; }
    function run() {
        input.wait(500);
        check(pill.shown && pill.grown === 1, "shown at the start");
        check(pill.mask.height === pill.height, "the whole pill takes the pointer");
        const hide = find(pill.contentItem, "Hide");
        check(!!hide && hide.visible, "Hide button");
        input.mouseClick(hide, hide.width / 2, hide.height / 2);
        check(pill.hidden, "Hide hides");
        const keep = find(pill.contentItem, "Keep shown");
        check(!!keep, "the button turns into Keep shown");
        input.mouseMove(pill.contentItem, pill.width / 2, pill.height - 2); // onto the strip
        // pretend the pointer left: no leave event can be faked, so drop the hover's linger only
        pill.hidden = false; pill.hidden = true;
        FocusMode.zen = false;
        input.wait(100);
        check(!pill.hidden, "leaving Zen forgets Hide");
        FocusMode.zen = true;
        input.wait(400);
        check(pill.shown && pill.grown === 1, "a new Zen session shows the pill again");
        input.mouseMove(pill.contentItem, -20, -20); // the pointer off the pill
        input.wait(100);
        return "PASS Hide, Keep shown, Hide forgotten when Zen ends";
    }
    IpcHandler {
        target: "pillTest"
        function ready(): bool { return pill.visible; }
        function run(): string { try { return root.run(); } catch (e) { return "FAIL " + e.message; } }
        function tuck(): string { pill.hidden = true; return "ok"; }
        function state(): string { return JSON.stringify({ hidden: pill.hidden, shown: pill.shown, grown: pill.grown, maskY: pill.mask.y, maskH: pill.mask.height, height: pill.height }); }
    }
}
