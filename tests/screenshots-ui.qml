import qs.popups
import qs.services
import Quickshell
import Quickshell.Io
import QtQuick
import QtTest

// Live screen capture, with system actions replaced by fixture services in the runner.
Scope {
    id: fixture
    ScreenshotPicker { id: picker }
    TestCase { id: input; when: false }
    function check(ok, message) { if (!ok) throw new Error(message); }
    function until(test) {
        for (let i = 0; i < 100 && !test(); i++) input.wait(20);
        check(test(), "timed out waiting for capture state");
    }
    function find(item, name) {
        if (item.objectName === name && item.visible) return item;
        for (const child of item.children) { const result = find(child, name); if (result) return result; }
        return null;
    }
    function menu() {
        if (picker.mode) picker.close();
        input.wait(240);
        picker.start("menu");
        until(() => picker.mode === "menu");
        input.wait(240);
    }
    function showPreview() {
        menu();
        for (let i = 0; i < 4; i++) input.keyClick(Qt.Key_Right);
        input.wait(750);
        check(picker.current === 4, "keyboard selection must stay on Lens");
        const bar = find(picker.contentItem, "screenshot-toolbar");
        const tip = find(picker.contentItem, "screenshot-tooltip");
        check(bar && bar.height === 62 && Math.abs(bar.y - 96) < 1, "board toolbar size and placement");
        check(tip && tip.x >= 16 && tip.x + tip.width <= picker.width - 16, "tooltip stays on screen");
        check(tip.Accessible.name.includes("ChatGPT"), "tooltip names the preferred provider");
        return JSON.stringify({ width: bar.width, height: bar.height, top: bar.y, tooltipWidth: tip.width });
    }
    function runChecks() {
        const images = [];
        menu();
        input.keyClick(Qt.Key_Left);
        check(picker.current === 6, "left wraps to Record");
        input.keyClick(Qt.Key_Right);
        check(picker.current === 0, "right wraps to Region");
        const lens = find(picker.contentItem, "screenshot-choice-lens");
        input.mouseMove(lens, lens.width / 2, lens.height / 2);
        check(picker.current === 4, "moving the pointer highlights Lens");
        input.wait(750);
        check(find(picker.contentItem, "screenshot-tooltip") !== null, "pointer tooltip opens after the delay");
        input.mouseMove(picker.contentItem, 20, 20); input.wait(250);
        check(find(picker.contentItem, "screenshot-tooltip") === null, "pointer tooltip closes on exit");
        input.mouseMove(lens, lens.width / 2, lens.height / 2); input.wait(750);
        check(find(picker.contentItem, "screenshot-tooltip") !== null, "pointer tooltip opens again");
        input.mouseClick(lens, lens.width / 2, lens.height / 2);
        check(picker.mode === "lens", "mouse selects Lens");
        picker.close();
        for (const action of [[Qt.Key_R,"region"],[Qt.Key_W,"window"],[Qt.Key_T,"text"],[Qt.Key_L,"lens"],[Qt.Key_V,"record"]]) {
            menu(); input.keyClick(action[0]); check(picker.mode === action[1], "shortcut " + action[1]);
            input.keyClick(Qt.Key_Escape); check(picker.mode === "", "Esc cancels " + action[1]);
        }
        menu(); input.keyClick(Qt.Key_C); input.wait(300);
        check(picker.mode === "" && Screenshots.picked === 1, "Colour dispatch waits for the menu to close");
        menu(); input.keyClick(Qt.Key_V);
        input.mouseClick(picker.contentItem, 600, 400); input.wait(300);
        check(Screenshots.recorded === 1 && Screenshots.recordWhole, "Record click selects whole screen");
        menu(); input.keyClick(Qt.Key_S); until(() => picker.mode === "");
        images.push({kind:"screen",path:Screenshots.lastPath,width:picker.width,height:picker.height});
        for (const action of [[Qt.Key_R,"region"],[Qt.Key_T,"text"],[Qt.Key_L,"lens"]]) {
            menu(); input.keyClick(action[0]);
            input.mousePress(picker.contentItem, 220, 300);
            input.mouseMove(picker.contentItem, 620, 480, 30);
            input.mouseRelease(picker.contentItem, 620, 480);
            until(() => picker.mode === "");
            const text = action[1] === "text";
            images.push({kind:action[1],path:action[1] === "lens" ? Lens.path : Screenshots.lastPath,width:text?800:400,height:text?360:180});
        }
        Lens.close();
        menu(); input.keyClick(Qt.Key_W);
        input.mouseMove(picker.contentItem, 300, 350, 30);
        check(picker.hovered !== null, "window hit testing");
        input.mouseClick(picker.contentItem, 300, 350);
        until(() => picker.mode === "");
        images.push({kind:"window",path:Screenshots.lastPath,width:400,height:180});
        Screenshots.hasPicker = false; Screenshots.hasRecorder = false;
        menu(); check(picker.choices.length === 5, "unavailable tools hidden");
        input.keyClick(Qt.Key_C); check(picker.mode === "menu", "unavailable Colour cannot launch");
        input.keyClick(Qt.Key_Escape);
        Screenshots.hasPicker = true; Screenshots.hasRecorder = true; Screenshots.recording = true;
        menu(); check(!picker.choices.some(c => c.name === "Record"), "Record hidden during recording");
        input.mouseClick(picker.contentItem, 20, picker.height - 20);
        check(picker.mode === "", "outside click closes the menu");
        input.wait(250);
        check(!picker.visible, "closing fade releases the overlay");
        return JSON.stringify(images);
    }
    IpcHandler {
        target: "screenshotTest"
        function ready(): bool { return true; }
        function pickerMode(): string { return picker.mode; }
        function preview(): string { try { return fixture.showPreview(); } catch(e) { return "FAIL: " + e.message; } }
        function run(): string { try { return fixture.runChecks(); } catch(e) { picker.close(); return "FAIL: " + e.message; } }
    }
}
