import qs
import qs.services
import QtQuick
import "highlight.js" as Highlight

// An answer in the quick chat (boards QuickChatAnswer/Replying): prose as Markdown, fenced code in its
// own dark block with Copy, and a "> " quote as a callout with a warning mark. `writing` adds the caret
// the Replying board shows after the text so far.
Column {
    id: root

    property string markdown
    property bool writing
    spacing: 12

    function blocks(text: string): var {
        const out = [], lines = text.split("\n");
        let prose = [], code = [], quote = [], fence = "", language = "";
        const flush = () => {
            if (prose.length && prose.join("").trim())
                out.push({ kind: "prose", text: prose.join("\n") });
            prose = [];
            if (quote.length)
                out.push({ kind: "quote", text: quote.join("\n") });
            quote = [];
        };
        for (const line of lines) {
            const match = line.match(/^\s*(`{3,}|~{3,})(.*)$/);
            if (!fence && match) {
                flush();
                fence = match[1];
                language = match[2].trim();
            } else if (fence && match && match[1][0] === fence[0] && match[1].length >= fence.length) {
                out.push({ kind: "code", text: code.join("\n"), language: language });
                code = [];
                fence = "";
            } else if (fence) {
                code.push(line);
            } else if (/^\s*>/.test(line)) {
                if (prose.length) {
                    out.push({ kind: "prose", text: prose.join("\n") });
                    prose = [];
                }
                quote.push(line.replace(/^\s*>\s?/, ""));
            } else {
                if (quote.length) {
                    out.push({ kind: "quote", text: quote.join("\n") });
                    quote = [];
                }
                prose.push(line);
            }
        }
        if (fence)
            out.push({ kind: "code", text: code.join("\n"), language: language }); // still being written
        flush();
        return out;
    }

    readonly property var parts: blocks(markdown)

    Repeater {
        model: root.parts

        Loader {
            id: block

            required property var modelData
            required property int index
            readonly property bool last: index === root.parts.length - 1
            width: root.width
            sourceComponent: modelData.kind === "code" ? codeView : modelData.kind === "quote" ? quoteView : proseView

            Component {
                id: proseView

                TextEdit {
                    text: block.modelData.text + (root.writing && block.last ? " ▍" : "")
                    textFormat: TextEdit.MarkdownText
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    color: Theme.text
                    selectionColor: Theme.overlay2
                    selectedTextColor: Theme.textBright
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    onLinkActivated: link => Chat.openLink(link)
                }
            }

            Component {
                id: codeView

                Rectangle {
                    implicitHeight: Math.max(44, code.implicitHeight + 24)
                    radius: 14
                    color: Theme.bg

                    TextEdit {
                        id: code
                        x: 14
                        y: 12
                        width: parent.width - 28 - 36
                        // coloured by its language (the fence's, or a guess)
                        text: Highlight.html(block.modelData.text, block.modelData.language ?? "", Theme.codeColours)
                        textFormat: TextEdit.RichText
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.WrapAnywhere
                        color: Theme.textBright
                        selectionColor: Theme.overlay2
                        font.family: Theme.fontMono
                        font.pixelSize: 12
                    }

                    ChatButton {
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        y: 6
                        size: 32
                        glyph: copied.running ? Icons.check : Icons.copy
                        tip: "Copy"
                        onClicked: {
                            Chat.copy(block.modelData.text);
                            copied.restart();
                        }
                    }

                    Timer {
                        id: copied
                        interval: 1500
                    }
                }
            }

            Component {
                id: quoteView

                Rectangle {
                    implicitHeight: Math.max(40, quote.implicitHeight + 20)
                    radius: 14
                    color: Theme.overlay

                    Icon {
                        x: 12
                        y: 11
                        size: 16
                        paths: Icons.triangleAlert
                        color: Theme.gold
                    }

                    TextEdit {
                        id: quote
                        x: 38
                        y: 10
                        width: parent.width - 50
                        text: block.modelData.text
                        textFormat: TextEdit.MarkdownText
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.Wrap
                        color: Theme.text
                        selectionColor: Theme.overlay2
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                }
            }
        }
    }
}
