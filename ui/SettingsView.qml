import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Glyphs.js" as Glyphs

// Omarchy has no settings screen for plugin widgets, so the panel is it.
Column {
  id: view

  required property var host
  readonly property var service: host.service
  readonly property var update: service ? service.update : ({})

  spacing: Style.space(12)

  readonly property string updateText: {
    if (update.busy) return update.applying ? "Updating…" : "Checking…"
    if (update.state === "current") return "Up to date"
    if (update.state === "outdated") return "Update"
    if (update.state === "failed") return "Retry"
    return "Check"
  }

  component Caption: Text {
    required property var host
    width: parent ? parent.width : implicitWidth
    wrapMode: Text.WordWrap
    color: host.dim
    font.family: host.fontFamily
    font.pixelSize: Style.font.caption
  }

  Item {
    width: parent.width
    implicitHeight: backButton.height

    PanelActionButton {
      id: backButton
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      iconText: Glyphs.back
      tooltipText: "Back (esc)"
      foreground: view.host.fg
      fontFamily: view.host.fontFamily
      onClicked: view.host.setView("mixer")
    }

    Text {
      anchors.left: backButton.right
      anchors.leftMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: "Settings"
      color: view.host.fg
      font.family: view.host.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }
  }

  PanelSeparator { foreground: view.host.fg }

  PanelSectionHeader {
    text: "GENERAL"
    foreground: view.host.fg
    fontFamily: view.host.fontFamily
  }

  Item {
    width: parent.width
    implicitHeight: Math.max(graphText.implicitHeight, graphSwitch.implicitHeight)

    Column {
      id: graphText
      anchors.left: parent.left
      anchors.leftMargin: Style.space(6)
      anchors.right: graphSwitch.left
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        text: "Virtual channels"
        color: view.host.fg
        font.family: view.host.fontFamily
        font.pixelSize: Style.font.body
      }

      Caption {
        host: view.host
        text: "Provide the Game, Chat, Media and Aux devices."
      }
    }

    ToggleSwitch {
      id: graphSwitch
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: view.service ? view.service.manageGraph : true
      foreground: view.host.fg
      onToggled: view.service.setManageGraph(!view.service.manageGraph)
    }
  }

  Item {
    visible: !!view.service && view.service.legacy
    width: parent.width
    implicitHeight: Math.max(legacyText.implicitHeight, legacyButton.implicitHeight)

    Caption {
      id: legacyText
      host: view.host
      anchors.left: parent.left
      anchors.leftMargin: Style.space(6)
      anchors.right: legacyButton.left
      anchors.rightMargin: Style.space(12)
      width: undefined
      text: "The Sonus desktop app is running, so routing is paused here."
    }

    Button {
      id: legacyButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: "Switch"
      tooltipText: "Stop the desktop app and its autostart; Sonus runs here from now on"
      bordered: true
      foreground: view.host.fg
      fontFamily: view.host.fontFamily
      fontSize: Style.font.caption
      onClicked: view.service.takeOver()
    }
  }

  PanelSeparator { foreground: view.host.fg }

  PanelSectionHeader {
    text: "SHORTCUT"
    foreground: view.host.fg
    fontFamily: view.host.fontFamily
  }

  Caption {
    host: view.host
    leftPadding: Style.space(6)
    text: "Ctrl+Alt+V opens this panel when bound in ~/.config/hypr/bindings.lua:"
  }

  Rectangle {
    width: parent.width
    height: code.implicitHeight + Style.space(12)
    radius: Style.cornerRadius > 0 ? Style.space(4) : 0
    color: Style.hoverFillFor(view.host.fg, Commons.Color.accent)

    Text {
      id: code
      x: Style.space(8)
      y: Style.space(6)
      width: parent.width - Style.space(16)
      wrapMode: Text.WrapAnywhere
      textFormat: Text.PlainText
      text: 'o.bind("CTRL + ALT + V", "Sonus", "omarchy-shell sonus toggle")'
      color: view.host.fg
      font.family: view.host.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  PanelSeparator { foreground: view.host.fg }

  PanelSectionHeader {
    text: "UPDATES"
    foreground: view.host.fg
    fontFamily: view.host.fontFamily
  }

  Item {
    width: parent.width
    implicitHeight: Math.max(versionText.implicitHeight, updateButton.implicitHeight)

    Text {
      id: versionText
      anchors.left: parent.left
      anchors.leftMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: view.service
        ? "Sonus " + view.service.version + (view.update.local ? "  ·  " + String(view.update.local).substring(0, 7) : "")
        : ""
      color: view.host.fg
      font.family: view.host.fontFamily
      font.pixelSize: Style.font.body
    }

    Button {
      id: updateButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: view.updateText
      selected: view.update.state === "outdated" && !view.update.busy
      enabled: !view.update.busy
      bordered: true
      foreground: view.host.fg
      fontFamily: view.host.fontFamily
      fontSize: Style.font.caption
      onClicked: view.service.updateClicked()
    }
  }
}
