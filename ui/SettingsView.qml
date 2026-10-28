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

  readonly property string updateState: update.state || "unknown"

  // How long ago the last check was, in words.
  function ago(seconds) {
    var s = Number(seconds || 0)
    if (s <= 0) return ""
    var minutes = Math.floor((Date.now() / 1000 - s) / 60)
    if (minutes < 1) return "just now"
    if (minutes < 60) return minutes + " min ago"
    var hours = Math.floor(minutes / 60)
    return hours < 24 ? hours + " h ago" : Math.floor(hours / 24) + " d ago"
  }

  readonly property string updateTitle: {
    if (update.busy && update.applying) return "Updating…"
    if (update.busy) return "Checking for updates…"
    if (updateState === "outdated") return update.version && update.version !== service.version
      ? "Sonus " + update.version + " is available"
      : "An update is available"
    if (updateState === "current") return "Up to date"
    if (updateState === "offline") return "Could not reach GitHub"
    if (updateState === "failed") return "The update did not go through"
    if (updateState === "unmanaged") return "Installed without git"
    return "Not checked yet"
  }

  readonly property string updateDetail: {
    if (update.busy && update.applying) return "Sonus reloads by itself when it is done."
    if (update.busy) return ""
    if (updateState === "outdated") {
      var parts = []
      if (update.summary) parts.push(update.summary)
      if (update.modified) parts.push("Your edits in the plugin folder are set aside with git stash first.")
      return parts.join("\n")
    }
    if (updateState === "failed") return update.message || "See ~/.local/state/sonus/update.log"
    if (updateState === "unmanaged") return "Reinstall with omarchy plugin add to get updates here."
    if (updateState === "current" || updateState === "offline") return "Checked " + ago(update.checked)
    return ""
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
        text: "Game, Chat, Media and Aux. Each output keeps its own volume and equalizer."
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
      // Broken by hand: wrapping left the closing paren alone on a line.
      wrapMode: Text.WrapAnywhere
      textFormat: Text.PlainText
      text: 'o.bind("CTRL + ALT + V", "Sonus",\n       "omarchy-shell sonus toggle")'
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
    implicitHeight: Math.max(updateText.implicitHeight, updateButton.implicitHeight)

    Column {
      id: updateText
      anchors.left: parent.left
      anchors.leftMargin: Style.space(6)
      anchors.right: updateButton.left
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: view.updateTitle
        color: view.updateState === "outdated" && !view.update.busy ? Commons.Color.accent : view.host.fg
        font.family: view.host.fontFamily
        font.pixelSize: Style.font.body
      }

      Caption {
        host: view.host
        visible: text !== ""
        textFormat: Text.PlainText
        text: view.updateDetail
      }
    }

    Button {
      id: updateButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      visible: view.updateState !== "unmanaged"
      text: view.update.busy ? (view.update.applying ? "Updating" : "Checking")
        : view.updateState === "outdated" ? "Update" : "Check now"
      iconText: view.update.busy ? Glyphs.sync : (view.updateState === "outdated" ? Glyphs.download : "")
      iconSpinning: !!view.update.busy
      tooltipText: view.updateState === "outdated"
        ? "Pull the new version and reload Sonus"
        : "Look for a new version on GitHub"
      selected: view.updateState === "outdated" && !view.update.busy
      enabled: !view.update.busy
      bordered: true
      foreground: view.host.fg
      fontFamily: view.host.fontFamily
      fontSize: Style.font.caption
      onClicked: {
        if (view.updateState === "outdated") view.service.applyUpdate()
        else view.service.checkUpdate(0)
      }
    }
  }

  Text {
    leftPadding: Style.space(6)
    textFormat: Text.PlainText
    text: view.service
      ? "Sonus " + view.service.version + (view.update.local ? "  ·  " + String(view.update.local).substring(0, 7) : "")
      : ""
    color: view.host.dim
    font.family: view.host.fontFamily
    font.pixelSize: Style.font.caption
  }
}
