import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Panel kit: the About section at the end of a plugin's settings. Its name
// and version, where updates stand beside a Check now or Update button, what
// an update brings, and optionally the automatic check. Fed by Updater.qml,
// or by Sonus's engine, which updates itself the same way.
Column {
  id: section

  property string icon: ""
  property string name: ""
  property string version: ""
  property string line: ""
  property bool available: false
  property bool checking: false
  property bool busy: false
  // Off when the plugin was installed without git.
  property bool managed: true
  property var notes: []
  property bool showAutoCheck: false
  property bool autoCheck: true
  property string autoCheckIcon: "󰔟"
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family

  signal checkRequested()
  signal applyRequested()
  signal autoCheckToggled()

  width: parent ? parent.width : implicitWidth
  spacing: Style.space(12)

  SectionHeader {
    icon: section.icon
    title: section.name.toUpperCase()
    detail: section.version !== "" ? "V" + section.version : ""
    foreground: section.foreground
    accent: section.accent
    fontFamily: section.fontFamily
  }

  Item {
    width: parent.width
    height: Math.max(updateButton.visible ? updateButton.implicitHeight : 0, lineText.implicitHeight)

    Caption {
      id: lineText
      anchors.left: parent.left
      anchors.right: updateButton.visible ? updateButton.left : parent.right
      anchors.rightMargin: updateButton.visible ? Style.space(10) : 0
      anchors.verticalCenter: parent.verticalCenter
      text: section.line
      foreground: section.foreground
      opacity: section.available ? 1 : 0.55
      fontFamily: section.fontFamily
    }

    Button {
      id: updateButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      visible: section.managed
      text: section.available ? "Update" : "Check now"
      iconText: section.available ? "󰇚" : "󰑓"
      iconSpinning: section.checking
      tooltipText: section.available ? "Download and reload " + section.name + ". Your settings are kept" : "Look for a newer " + section.name
      fontSize: Style.font.bodySmall
      foreground: section.foreground
      fontFamily: section.fontFamily
      bordered: true
      opacity: section.busy ? 0.45 : 1
      onClicked: {
        if (section.busy) return
        if (section.available) section.applyRequested()
        else section.checkRequested()
      }
    }
  }

  Column {
    width: parent.width
    spacing: Style.space(2)
    visible: section.notes.length > 0

    Repeater {
      model: section.notes

      Caption {
        required property string modelData
        width: parent.width
        maximumLineCount: 2
        elide: Text.ElideRight
        text: "· " + modelData
        foreground: section.foreground
        opacity: 0.7
        fontFamily: section.fontFamily
      }
    }
  }

  SwitchRow {
    visible: section.showAutoCheck && section.managed
    icon: section.autoCheckIcon
    label: "Check for updates automatically"
    hint: "Looks on GitHub every few hours; updating is always your click"
    checked: section.autoCheck
    foreground: section.foreground
    accent: section.accent
    fontFamily: section.fontFamily
    onToggled: section.autoCheckToggled()
  }
}
