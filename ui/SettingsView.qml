import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Glyphs.js" as Glyphs

// Omarchy has no settings screen for plugin widgets, so the panel is it.
// Laid out like the other plugins' settings: the hero with a way back, then
// sections from the panel kit, ending in About and updates.
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

  // The same words as the other plugins' About sections.
  readonly property string updateLine: {
    if (update.busy && update.applying) return "Updating…"
    if (update.busy) return "Checking…"
    if (updateState === "outdated") {
      var line = update.version && update.version !== service.version
        ? "Version " + update.version + " is available" : "An update is available"
      return update.modified ? line + ". Your edits in the plugin folder are set aside first." : line
    }
    if (updateState === "current") return "Up to date · checked " + ago(update.checked)
    if (updateState === "offline") return "Couldn't reach GitHub"
    if (updateState === "failed") return update.message || "The update didn't go through"
    if (updateState === "unmanaged") return "Installed without git, so it can't update itself"
    return "Not checked yet"
  }

  PanelHero {
    width: parent.width
    title: "Settings"
    meta: "Changes save as you make them"
    foreground: view.host.fg
    fontFamily: view.host.fontFamily
    iconComponent: Component {
      SonusMark {
        width: Style.font.display
        height: width
        color: view.host.fg
        muted: !!(view.service && view.service.masterMuted)
      }
    }
    trailingControl: Component {
      PanelActionButton {
        iconText: Glyphs.back
        tooltipText: "Back to the mixer (esc)"
        foreground: view.host.fg
        fontFamily: view.host.fontFamily
        onClicked: view.host.setView("mixer")
      }
    }
  }

  PanelSeparator { foreground: view.host.fg }

  SectionHeader {
    icon: Glyphs.cog
    title: "GENERAL"
    foreground: view.host.fg
    fontFamily: view.host.fontFamily
  }

  SwitchRow {
    icon: Glyphs.sliders
    label: "Virtual channels"
    hint: "Game, Chat, Media and Aux. Each output keeps its own volume and equalizer."
    checked: view.service ? view.service.manageGraph : true
    foreground: view.host.fg
    fontFamily: view.host.fontFamily
    onToggled: view.service.setManageGraph(!view.service.manageGraph)
  }

  Notice {
    visible: !!view.service && view.service.legacy
    tone: "urgent"
    icon: Glyphs.alert
    text: "The Sonus desktop app is running, so routing is paused here."
    actionLabel: "Switch"
    foreground: view.host.fg
    fontFamily: view.host.fontFamily
    onActioned: view.service.takeOver()
  }

  PanelSeparator { foreground: view.host.fg }

  SectionHeader {
    icon: Glyphs.keyboard
    title: "SHORTCUT"
    foreground: view.host.fg
    fontFamily: view.host.fontFamily
  }

  Caption {
    width: parent.width
    text: "Ctrl+Alt+V opens this panel when bound in ~/.config/hypr/bindings.lua:"
    foreground: view.host.fg
    fontFamily: view.host.fontFamily
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

  UpdateSection {
    icon: Glyphs.update
    name: "Sonus"
    version: view.service ? view.service.version : ""
    line: view.updateLine
    available: view.updateState === "outdated" && !view.update.busy
    checking: !!view.update.busy && !view.update.applying
    busy: !!view.update.busy
    managed: view.updateState !== "unmanaged"
    notes: view.updateState === "outdated" && view.update.summary ? [view.update.summary] : []
    foreground: view.host.fg
    fontFamily: view.host.fontFamily
    onCheckRequested: view.service.checkUpdate(0)
    onApplyRequested: view.service.applyUpdate()
  }
}
