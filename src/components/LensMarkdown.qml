import qs
import qs.services
import QtQuick

// Native Markdown for prose; separate code cards keep mono text and a real Copy button.
Column {
    id: root
    property string markdown
    spacing: 14

    function blocks(text: string): var {
        const out = [], lines = text.split("\n");
        let prose = [], code = [], fence = "", language = "";
        for (const line of lines) {
            const match = line.match(/^\s*(`{3,}|~{3,})(.*)$/);
            if (!fence && match) {
                if (prose.length) out.push({ code: false, text: prose.join("\n") });
                prose = [];
                fence = match[1];
                language = match[2].trim();
            } else if (fence && match && match[1][0] === fence[0] && match[1].length >= fence.length) {
                out.push({ code: true, text: code.join("\n"), language: language });
                code = [];
                fence = "";
            } else if (fence) code.push(line);
            else prose.push(line);
        }
        if (fence) out.push({ code: true, text: code.join("\n"), language: language });
        if (prose.length) out.push({ code: false, text: prose.join("\n") });
        return out;
    }

    Repeater {
        model: root.blocks(root.markdown)
        Loader {
            id: block
            required property var modelData
            width: root.width
            sourceComponent: modelData.code ? codeView : proseView

            Component {
                id: proseView
                TextEdit {
                    // Answers may contain links; images are already represented by the snip.
                    text: block.modelData.text.replace(/!\[([^\]]*)\]\([^)]*\)/g, "$1")
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
                    onLinkActivated: link => Lens.openLink(link)
                }
            }
            Component {
                id: codeView
                Rectangle {
                    implicitHeight: codeColumn.implicitHeight + 24
                    radius: Theme.tileRadius
                    color: Theme.overlay
                    Column {
                        id: codeColumn
                        x: 12; y: 12
                        width: parent.width - 24
                        spacing: 8
                        Item {
                            width: parent.width
                            height: 28
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: block.modelData.language || "Code"
                                color: Theme.textBright
                                font.family: Theme.fontUi
                                font.pixelSize: 12
                                font.weight: Font.Bold
                            }
                            GhostButton {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                icon: Icons.copy
                                label: "Copy code"
                                onClicked: Clipboard.copyText(block.modelData.text)
                            }
                        }
                        Rectangle {
                            width: parent.width
                            height: codeText.contentHeight + 24
                            radius: 14
                            color: Theme.bg
                            Flickable {
                                x: 12; y: 12
                                width: parent.width - 24
                                height: parent.height - 24
                                contentWidth: Math.max(width, codeText.contentWidth)
                                contentHeight: height
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                TextEdit {
                                    id: codeText
                                    width: Math.max(implicitWidth, parent.width)
                                    text: block.modelData.text
                                    textFormat: TextEdit.PlainText
                                    readOnly: true
                                    selectByMouse: true
                                    color: Theme.text
                                    selectionColor: Theme.overlay2
                                    selectedTextColor: Theme.textBright
                                    font.family: Theme.fontMono
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
