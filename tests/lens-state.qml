import qs.services
import qs.components
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Window
import QtTest

// Offscreen only: the prompt, confirmation input and real helper pipe with fake CLIs.
Scope {
    LensInput { id: input; width: 536; height: implicitHeight; initial: true }
    Window {
        visible: true; width: 480; height: 420
        LensUpgrade { id: upgrade; anchors.fill: parent }
        LensImages { id: images; width: 440; y: 300 }
    }
    TestCase { id: keys; when: false }

    function findNamed(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children) {
            const found = findNamed(child, name);
            if (found) return found;
        }
        return null;
    }
    IpcHandler {
        target: "lensTest"
        function beginFixture(file: string): void { Lens.begin(file, Qt.rect(0, 0, 600, 200), null); }
        function chooseImageFixture(): void { Lens.attachImage(); }
        function removeImageFixture(imageId: int): void { Lens.removeImage(imageId); }
        function clickRemoveSecondImageFixture(): void {
            const target = findNamed(images, "lensRemoveImage_2");
            if (target) keys.mouseClick(target, 22, 22);
        }
        function snipFixture(): void { Lens.requestSnip(); }
        function resumeSnipsFixture(): void { Lens.resumeSnips(); }
        function repeatBothFixture(): void { Lens.askBoth(Lens.question); }
        function bothFixture(): void { Lens.askBoth("Compare these images"); }
        function imageUiState(): string {
            return JSON.stringify({ first: !!findNamed(images, "lensImageNumber_1"),
                second: !!findNamed(images, "lensImageNumber_2"), third: !!findNamed(images, "lensImageNumber_3"),
                height: images.implicitHeight, width: images.width });
        }
        function chooseFixture(): void { Lens.attachFile(); }
        function askFixture(): void { Lens.ask("Fix the attached file"); }
        function transferFixture(): void { Lens.askOther(); }
        function applyFixture(): void { Lens.review(true); }
        function taskFixture(task: string): void { Lens.askTask("Translate this code", task); }
        function keepFixture(): void { keys.keyClick(Qt.Key_Return); }
        function acceptFixture(): void { keys.keyClick(Qt.Key_Right); keys.keyClick(Qt.Key_Return); }
        function suggestFixture(on: bool): void { ShellSettings.setLensSuggestCoding(on); }
        function fixtureState(): string {
            return JSON.stringify({ images: Lens.images, capturing: Lens.capturingImage, open: Lens.open, combined: Lens.combined, ready: Lens.ready, state: Lens.state, attachment: Lens.attachment,
                picking: Lens.pickingFile, provider: Lens.provider, preferred: ShellSettings.lensProvider,
                diff: Lens.diff, notice: Lens.notice, model: Lens.model, effort: Lens.effort,
                upgrade: Lens.upgradePrompt, enabled: Lens.codingEnabled, asked: Lens.codingAsked,
                normalClaude: ShellSettings.lensClaudeModel, normalCodex: ShellSettings.lensCodexModel });
        }
        function inputText(text: string): void { input.text = text; }
        function inputEnd(): void { findNamed(input, "lensInputField").cursorPosition = input.text.length; }
        function inputState(): string {
            const field = findNamed(input, "lensInputField");
            const scroll = findNamed(input, "lensInputScroll");
            return JSON.stringify({ height: input.height, contentHeight: field.contentHeight,
                textTop: field.mapToItem(input, 0, field.topPadding).y, viewport: scroll.height,
                topPadding: field.topPadding, bottomPadding: field.bottomPadding,
                cursorTop: field.mapToItem(input, 0, field.cursorRectangle.y).y,
                cursorHeight: field.cursorRectangle.height, contentY: scroll.contentY });
        }
        function check(): string {
            Lens.answer = "Previous answer";
            Lens.lastAnswer = { provider: "codex", model: "gpt-6-luna", effort: "low", seconds: 4, question: "Original question" };
            Lens.provider = "claude";
            Lens.model = "sonnet";
            Lens.effort = "high";
            Lens.seconds = 20;
            Lens.question = "Cancelled follow-up";
            Lens.state = "reading";
            Lens.cancelled();
            if (Lens.provider !== "codex" || Lens.model !== "gpt-6-luna" || Lens.effort !== "low" || Lens.seconds !== 4 || Lens.question !== "Original question" || Lens.answer !== "Previous answer" || Lens.state !== "answer" || !Lens.stoppedRequest)
                return "FAIL: cancelled follow-up lost the previous answer's metadata";
            Lens.answer = "";
            Lens.lastAnswer = null;
            Lens.question = "First question";
            Lens.state = "reading";
            Lens.cancelled();
            if (Lens.state !== "prompt" || Lens.question !== "First question")
                return "FAIL: cancelled first request lost the question";
            return "all passed";
        }
    }
}
