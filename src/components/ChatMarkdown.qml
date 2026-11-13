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
                    font.pixelSize: Theme.tui ? Theme.tuiTextSize : 13
                    font.weight: Font.Medium
                    onLinkActivated: link => Chat.openLink(link)
                }
            }

            Component {
                id: codeView

                // TUI (QuickChatReplying board): a frame with the language in its tab and "[c] copy" on
                // its top edge; the frame's tab needs ten pixels above it
                Item {
                    implicitHeight: codeFrame.height + (Theme.tui ? 10 : 0)

                PanelFrame {
                    id: codeFrame
                    y: Theme.tui ? 10 : 0
                    width: parent.width
                    height: Math.max(44, code.implicitHeight + (Theme.tui ? 28 : 24))
                    title: Theme.tui ? (block.modelData.language || "code") : ""
                    active: false
                    radius: Theme.tui ? 0 : 14
                    color: Theme.tui ? Theme.bgAlt : Theme.bg
                    border.width: Theme.tui ? 1 : 0

                    TextEdit {
                        id: code
                        x: Theme.tui ? 12 : 14
                        y: Theme.tui ? 16 : 12
                        width: parent.width - x * 2 - (Theme.tui ? 0 : 36)
                        // coloured by its language (the fence's, or a guess)
                        text: Highlight.html(block.modelData.text, block.modelData.language ?? "", Theme.codeColours)
                        textFormat: TextEdit.RichText
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.WrapAnywhere
                        color: Theme.textBright
                        selectionColor: Theme.overlay2
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.tui ? Theme.tuiTextSize : 12
                    }

                    // [c] copy, on the frame's top edge (TUI)
                    Rectangle {
                        visible: Theme.tui
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        y: -10
                        width: copyText.implicitWidth + 16
                        height: Theme.tuiLineHeight
                        color: copyMouse.containsMouse ? Theme.tuiHover : Theme.bg
                        Accessible.role: Accessible.Button
                        Accessible.name: "Copy"

                        Text {
                            id: copyText
                            anchors.centerIn: parent
                            textFormat: Text.StyledText
                            text: copied.running ? "copied" : `<b><font color="${Theme.textBright}">[c]</font></b> copy`
                            color: Theme.subtext
                            font.family: Theme.fontTui
                            font.pixelSize: Theme.tuiTextSize
                        }

                        MouseArea {
                            id: copyMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Chat.copy(block.modelData.text);
                                copied.restart();
                            }
                        }
                    }

                    ChatButton {
                        visible: !Theme.tui
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
            }

            Component {
                id: quoteView

                Rectangle {
                    implicitHeight: Math.max(40, quote.implicitHeight + 20)
                    radius: Theme.tui ? 0 : 14
                    color: Theme.tui ? Theme.bgAlt : Theme.overlay

                    Text {
                        visible: Theme.tui
                        x: 12
                        y: 10
                        text: "[!]"
                        color: Theme.gold
                        font.family: Theme.fontTui
                        font.pixelSize: Theme.tuiTextSize
                        font.weight: Font.Bold
                    }

                    Icon {
                        visible: !Theme.tui
                        x: 12
                        y: 11
                        size: 16
                        paths: Icons.triangleAlert
                        color: Theme.gold
                    }

                    TextEdit {
                        id: quote
                        x: Theme.tui ? 44 : 38
                        y: 10
                        width: parent.width - x - 12
                        text: block.modelData.text
                        textFormat: TextEdit.MarkdownText
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.Wrap
                        color: Theme.text
                        selectionColor: Theme.overlay2
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.tui ? Theme.tuiTextSize : 12
                        font.weight: Font.Medium
                    }
                }
            }
        }
    }
}
