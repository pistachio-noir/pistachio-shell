import qs
import qs.components
import qs.services
import QtQuick

Column {
    id: root
    spacing: 14
    Rectangle {
        objectName: "setting-provider"
        width: parent.width; height: 68; radius: Theme.tileRadius; color: Theme.overlay
        Column { x:18;anchors.verticalCenter:parent.verticalCenter;spacing:3;SettingsText{text:"Preferred provider"}SettingsText{text:"Used for your next question.";secondary:true} }
        Row {
            anchors.right:parent.right;anchors.rightMargin:18;anchors.verticalCenter:parent.verticalCenter;spacing:3
            SettingsButton { width:104;text:"Claude";active:ShellSettings.lensProvider==="claude";onClicked:ShellSettings.setLensChoice("lensProvider","claude") }
            SettingsButton { width:104;text:"ChatGPT";active:ShellSettings.lensProvider==="codex";onClicked:ShellSettings.setLensChoice("lensProvider","codex") }
        }
    }
    SettingsGroup {
        width: parent.width
        rows: [{ id: "coding", kind: "toggle", title: "Suggest a coding model", subtitle: () => "Ask once per snip, for coding only. Other tasks keep the normal model.", checked: () => ShellSettings.lensSuggestCoding, toggle: () => ShellSettings.setLensSuggestCoding(!ShellSettings.lensSuggestCoding) }]
    }
    Row {
        width: parent.width; spacing: 14
        Repeater {
            model: ["Claude", "Codex"]
            Rectangle {
                id: card
                required property string modelData
                width: (root.width - 14) / 2; height: fields.height + 36
                radius: Theme.tileRadius; color: Theme.overlay
                readonly property string prefix: "lens" + modelData
                Column {
                    id: fields
                    x: 18; y: 18; width: parent.width - 36; spacing: 14
                    Row {
                        spacing: 10
                        Rectangle { width: 36; height: 36; radius: 18; color: Theme.overlay2; Icon { anchors.centerIn: parent; size: 18; paths: Icons.sparkles; color: card.modelData === "Claude" ? Theme.clay : Theme.sageBlue } }
                        Column { SettingsText { text: card.modelData === "Claude" ? "Claude" : "ChatGPT" } SettingsText { text: card.modelData === "Claude" ? "Claude Code" : "Codex CLI"; secondary: true } }
                    }
                    Row {
                        width: parent.width; spacing: 12
                        Column { width: parent.width - 122; spacing: 7
                            SettingsText { text: "Model"; secondary: true; font.pixelSize: 11 }
                            SettingsChoice { objectName: "choice-"+card.prefix+"Model"; width: parent.width; height: 50; choices: ShellSettings.lensChoices[card.prefix+"Model"]; selected: Store.saved[card.prefix+"Model"]; onChosen: value=>ShellSettings.setLensChoice(card.prefix+"Model",value); Accessible.name: card.modelData+" model" }
                        }
                        Column { width: 110; spacing: 7
                            SettingsText { text: "Effort"; secondary: true; font.pixelSize: 11 }
                            SettingsChoice { objectName: "choice-"+card.prefix+"Effort"; width: parent.width; height: 50; choices: ShellSettings.lensChoices[card.prefix+"Effort"]; selected: Store.saved[card.prefix+"Effort"]; onChosen: value=>ShellSettings.setLensChoice(card.prefix+"Effort",value); Accessible.name: card.modelData+" effort" }
                        }
                    }
                    SettingsRow {
                        width: parent.width; height: 80; divided: true
                        horizontalPadding: 0
                        spec: ({id:card.modelData.toLowerCase(),kind:"toggle",title:card.modelData === "Claude" ? "Fall back to ChatGPT" : "Fall back to Claude",subtitle:()=>"If unavailable · one attempt",checked:()=>Store.saved[card.prefix+"Fallback"],toggle:()=>ShellSettings.setLensFallback(card.modelData.toLowerCase(),!Store.saved[card.prefix+"Fallback"])})
                    }
                    Rectangle { width: parent.width; height: 1; color: Theme.overlay2 }
                    SettingsText { text: "Coding only" }
                    Row {
                        width: parent.width; spacing: 12
                        Column { width: parent.width - 122; spacing: 7
                            SettingsText { text: "Model"; secondary: true; font.pixelSize: 11 }
                            SettingsChoice { objectName: "choice-"+card.prefix+"CodingModel"; width: parent.width; height: 50; choices: ShellSettings.lensChoices[card.prefix+"CodingModel"]; selected: Store.saved[card.prefix+"CodingModel"]; onChosen: value=>ShellSettings.setLensChoice(card.prefix+"CodingModel",value); Accessible.name: card.modelData+" coding model" }
                        }
                        Column { width: 110; spacing: 7
                            SettingsText { text: "Effort"; secondary: true; font.pixelSize: 11 }
                            SettingsChoice { objectName: "choice-"+card.prefix+"CodingEffort"; width: parent.width; height: 50; choices: ShellSettings.lensChoices[card.prefix+"CodingEffort"]; selected: Store.saved[card.prefix+"CodingEffort"]; onChosen: value=>ShellSettings.setLensChoice(card.prefix+"CodingEffort",value); Accessible.name: card.modelData+" coding effort" }
                        }
                    }
                }
            }
        }
    }
}
