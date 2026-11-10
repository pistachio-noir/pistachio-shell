import qs.services
import qs.components
import Quickshell
import Quickshell.Io
import QtQuick

// No windows or CLI calls. Exercise cancellation state and the real prompt's geometry.
Scope {
    LensInput { id: input; width: 536; height: implicitHeight; initial: true }

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
            Lens.lastAnswer = { provider: "codex", model: "gpt-6-luna", seconds: 4, question: "Original question" };
            Lens.provider = "claude";
            Lens.model = "sonnet";
            Lens.seconds = 20;
            Lens.question = "Cancelled follow-up";
            Lens.state = "reading";
            Lens.cancelled();
            if (Lens.provider !== "codex" || Lens.model !== "gpt-6-luna" || Lens.seconds !== 4 || Lens.question !== "Original question" || Lens.answer !== "Previous answer" || Lens.state !== "answer" || !Lens.stoppedRequest)
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
