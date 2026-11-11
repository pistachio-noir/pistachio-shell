import qs
import qs.services
import QtQuick

Column {
    id: root
    objectName: "setting-reset"
    required property string page
    spacing: 10
    readonly property bool reviewing: SettingsReset.reviewing === page
    readonly property var changes: SettingsReset.changes(page)
    SettingsButton { objectName:"reset-review";visible:!root.reviewing;text:"Reset page preferences…";quiet:true;enabled:Store.ready;onClicked:SettingsReset.review(root.page) }
    Rectangle {
        visible:root.reviewing;width:parent.width;height:body.implicitHeight+36;radius:Theme.tileRadius;color:Theme.overlay
        Column {
            id:body;x:18;y:18;width:parent.width-36;spacing:10
            SettingsText { text:"Review page reset";font.weight:Font.Bold }
            SettingsText { width:parent.width;text:root.changes.length ? "These shell preferences will return to their defaults:" : "This page already uses its default shell preferences.";secondary:true }
            Repeater { model:root.changes;SettingsText { required property var modelData;width:body.width;text:modelData.title + " → " + SettingsReset.shown(modelData.value);font.pixelSize:12 } }
            SettingsText { width:parent.width;text:"Device choices, levels, connections, pairings, credentials and saved content are kept.";secondary:true;font.pixelSize:11 }
            Row { spacing:8
                SettingsButton { objectName:"reset-cancel";text:"Cancel";onClicked:SettingsReset.cancel() }
                SettingsButton { objectName:"reset-apply";text:"Reset preferences";enabled:root.changes.length>0;danger:true;onClicked:SettingsReset.apply(root.page) }
            }
        }
    }
}
