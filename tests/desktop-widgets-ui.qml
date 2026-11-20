import qs
import qs.panels
import qs.popups
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtTest

// tests/desktop-widgets.test.py's fixture: the real widget layer, studio and DesktopWidgets service,
// with stand-in Store, Compositor, FocusMode, SystemStats, Weather and Desktop.
ShellRoot {
    id: root
    PanelWindow {
        id: desk
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Background
        DesktopWidgetLayer { id: layer; anchors.fill: parent }
    }
    WidgetStudio { id: studio }
    TestCase { id: input; parent: studio.contentItem; when: false }
    function check(ok, why) { if (!ok) throw Error(why); }
    function find(item, name) { if (item.objectName === name) return item; for (const c of item.children ?? []) { const hit = find(c, name); if (hit) return hit; } return null; }
    function kinds() { return DesktopWidgets.layout.map(w => `${w.kind}@${w.col},${w.row}`).join(" "); }
    function run() {
        input.wait(400);
        const C = DesktopWidgets.columns;
        check(DesktopWidgets.cellWidth === 52 && DesktopWidgets.top === DesktopWidgets.margin, "half-cells from the top-left margin in Classic");
        check(kinds() === `clock@${C - 6},0 weather@${C - 4},4 stats@${C - 4},8`, "default layout down the right edge: " + kinds());
        check(layer.visible && DesktopWidgets.shown, "shown on an empty desktop");
        check(SystemStats.widgetWatchers === 1, "the stats block reads while shown: " + SystemStats.widgetWatchers);
        check(DesktopWidgets.cells.indexOf(`${Math.floor((C - 6) / 2)},0`) >= 0, "the icon cells under the clock are blocked: " + DesktopWidgets.cells);
        // a tiled window hides them and stops the readings; a floating one doesn't
        Compositor.windows = [{ workspace: 1, floating: true, hidden: false, minimized: false }];
        input.wait(50);
        check(DesktopWidgets.shown, "a floating window leaves them");
        Compositor.windows = [{ workspace: 1, floating: false, hidden: false, minimized: false }];
        input.wait(Theme.motionDuration + 150);
        check(!DesktopWidgets.shown && !layer.visible && SystemStats.widgetWatchers === 0, "a tiled window hides them, readings stop");
        Compositor.windows = [];
        FocusMode.zen = true;
        input.wait(50);
        check(!DesktopWidgets.shown, "hidden in Zen");
        FocusMode.zen = false;
        // the studio
        Store.saved.desktopWidgets = false;
        DesktopWidgets.arrange();
        input.wait(Theme.motionDuration + 150);
        check(studio.visible && DesktopWidgets.enabled, "arrange opens the studio and switches them on");
        const stage = find(studio.contentItem, "studio-stage");
        const clock = find(stage, "studio-clock"), weather = find(stage, "studio-weather");
        check(clock && weather, "studio blocks");
        // drag the clock to the top-left cell
        input.mousePress(clock, 20, 20);
        input.mouseMove(stage, clock.x + 40, clock.y + 20);
        input.mouseMove(stage, DesktopWidgets.margin + 6 + 20 + 10, DesktopWidgets.margin + 6 + 20 + 10);
        input.mouseRelease(stage, DesktopWidgets.margin + 6 + 20 + 10, DesktopWidgets.margin + 6 + 20 + 10);
        input.wait(50);
        check(kinds().startsWith("clock@0,0 "), "the clock snapped to 0,0: " + kinds());
        check(JSON.stringify(Store.saved.widgetLayout[0]) === '{"kind":"clock","col":0,"row":0,"u":52}', "saved: " + JSON.stringify(Store.saved.widgetLayout));
        // the weather onto the clock: refused, it goes back
        const before = kinds();
        input.mousePress(weather, 20, 20);
        input.mouseMove(stage, weather.x + 60, weather.y + 20);
        input.mouseMove(stage, DesktopWidgets.margin + 6 + 20 + 104, DesktopWidgets.margin + 6 + 20);
        input.mouseRelease(stage, DesktopWidgets.margin + 6 + 20 + 104, DesktopWidgets.margin + 6 + 20);
        input.wait(Theme.motionDuration + 100);
        check(kinds() === before, "a drop on another widget is refused: " + kinds());
        const w = DesktopWidgets.layout.find(x => x.kind === "weather");
        check(Math.abs(weather.x - (DesktopWidgets.xOf(w.col) + 6)) < 1, "the weather went back to its place");
        // the centre cross brightens while the dragged widget's middle is on it
        const cross = find(stage, "studio-cross");
        const mid = DesktopWidgets.middleX - 4 * 52 / 2 + 6; // the weather's x with its middle on the line
        input.mousePress(weather, 20, 20);
        input.mouseMove(stage, weather.x + 40, weather.y + 20);
        input.mouseMove(stage, mid + 20, weather.y + 20);
        input.wait(30);
        check(cross.onX, "the vertical line lights up in the middle");
        input.mouseRelease(stage, mid + 20, weather.y + 20);
        input.wait(50);
        const placed = DesktopWidgets.layout.find(x => x.kind === "weather");
        check(DesktopWidgets.xOf(placed.col) + 2 * 52 === DesktopWidgets.middleX, "the weather sits centred: " + kinds());
        // the new blocks come from +
        for (const k of ["media", "timers", "system"]) {
            const b = find(stage, "add-" + k);
            check(b && b.enabled, "+ offered for " + k);
            input.mouseClick(b);
            input.wait(30);
            check(DesktopWidgets.has(k), "+ adds " + k);
        }
        // ✕ and +
        input.mouseClick(find(stage, "remove-stats"));
        input.wait(50);
        check(!DesktopWidgets.has("stats"), "✕ removes");
        const add = find(stage, "add-stats");
        check(add && add.enabled, "+ CPU/RAM offered");
        input.mouseClick(add);
        input.wait(50);
        check(DesktopWidgets.has("stats"), "+ adds it back");
        // TUI: the grid starts under the 35 px strip
        Theme.tui = true;
        input.wait(50);
        check(DesktopWidgets.top === Theme.tuiBarHeight + DesktopWidgets.margin && DesktopWidgets.yOf(0) >= Theme.tuiBarHeight + 24, "TUI grid below the strip: top " + DesktopWidgets.top);
        Theme.tui = false;
        input.wait(50);
        // Esc closes
        input.keyClick(Qt.Key_Escape);
        input.wait(Theme.motionDuration + 150);
        check(!DesktopWidgets.arranging && !studio.visible, "Esc closes the studio");
        return "PASS half-cell layout, visibility, readings, studio drag/refuse/centre cross/remove/add (all six)/TUI offset/Esc";
    }
    IpcHandler {
        target: "widgetsTest"
        function ready(): bool { return Quickshell.screens.length > 0; }
        function run(): string { try { return root.run(); } catch (e) { return "FAIL " + e.message; } }
    }
}
