import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Glyphs.js" as Glyphs

// Omarchy has no settings screen for plugin widgets, so the panel is it.
// The rooms' hero with a way back, then sections from the panel kit, as the
// other plugins lay out their settings, ending in About and updates. The
// kit's icons come out as pixel art through Glyph.qml.
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

  HeroBlock {
    id: hero
    width: parent.width
    host: view.host
    logo: true
    muted: !!(view.service && view.service.masterMuted)
    title: "Settings"
    line: "Changes save as you make them"

    PixelButton {
      icon: "arrow-left"
      nudge: Math.round(view.host.gearTurn * 2)
      tooltipText: "Back to the mixer (esc)"
      foreground: view.host.fg
      fontFamily: view.host.fontFamily
      onClicked: view.host.setView("mixer")
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
    hint: "Game, Chat, Media and Aux, mixed per output"
    checked: view.service ? view.service.manageGraph : true
    foreground: view.host.fg
    fontFamily: view.host.fontFamily
    onToggled: view.service.setManageGraph(!view.service.manageGraph)
  }

  Notice {
    visible: !!view.service && view.service.legacy
    tone: "urgent"
    icon: Glyphs.alert
    text: view.host.legacyLine
    actionLabel: "Switch"
    foreground: view.host.fg
    fontFamily: view.host.fontFamily
    onActioned: view.service.takeOver()
  }

  // With reduced motion the spectrum stays off whatever the switch says,
  // so the switch shows it off and cannot be turned.
  SwitchRow {
    icon: Glyphs.music
    label: "Visualizer"
    hint: Style.reduceMotion ? "Off while reduced motion is on" : "A spectrum of what's playing, behind the title. Off with reduced motion."
    checked: !Style.reduceMotion && (view.service ? view.service.visualizer : true)
    interactive: !Style.reduceMotion
    foreground: view.host.fg
    fontFamily: view.host.fontFamily
    onToggled: view.service.setVisualizer(!view.service.visualizer)
  }

  // cava comes from Arch's repos. Sonus asks to install it on its own only
  // right after an update that said so; otherwise this button asks. A closed
  // password prompt or a failed pacman lands here.
  Notice {
    visible: !!view.service && view.service.visualizer && !Style.reduceMotion && view.service.engineUp && !view.service.cavaInstalled
    tone: view.service && view.service.cavaMessage !== "" ? "urgent" : "accent"
    icon: Glyphs.download
    busy: !!view.service && view.service.cavaInstalling
    text: {
      var sv = view.service
      if (!sv) return ""
      if (sv.cavaInstalling) return "Installing cava…"
      if (sv.cavaMessage !== "" && sv.cavaMessageFinal) return sv.cavaMessage + "."
      return (sv.cavaMessage !== "" ? sv.cavaMessage + ". " : "") + "Install cava to see the visualizer."
    }
    actionLabel: "Install"
    foreground: view.host.fg
    fontFamily: view.host.fontFamily
    onActioned: view.service.installCava()
  }

  PanelSeparator { foreground: view.host.fg }

  SectionHeader {
    icon: Glyphs.keyboard
    title: "SHORTCUT"
    foreground: view.host.fg
    fontFamily: view.host.fontFamily
  }

  // The chord, as the key it is. Sonus writes the bind itself, so all this
  // says is whether that has happened yet.
  Item {
    readonly property bool bound: !!view.service && view.service.shortcutStatus === "installed"
    width: parent.width
    implicitHeight: Math.max(chord.height, shortcutLine.implicitHeight)

    Glyph {
      id: shortcutIcon
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(22)
      icon: Glyphs.keyboard
      size: Style.font.title
      color: view.host.fg
      fontFamily: view.host.fontFamily
    }

    MonoText {
      step: "body"
      fontFamily: view.host.fontFamily
      id: shortcutLine
      anchors.left: shortcutIcon.right
      anchors.leftMargin: Style.space(10)
      anchors.right: chord.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      wrapMode: Text.Wrap
      textFormat: Text.PlainText
      text: parent.bound ? "Opens this panel" : "Setting up the bind"
      color: parent.bound ? view.host.fg : view.host.dim
    }

    CursorSurface {
      id: chord
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: chordText.implicitWidth + Style.space(12)
      height: chordText.implicitHeight + Style.space(6)
      bordered: true
      foreground: view.host.fg

      MonoText {
        step: "small"
        fontFamily: view.host.fontFamily
        id: chordText
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: "Ctrl+Alt+V"
        color: view.host.fg
      }

      HoverHandler { id: chordHover }

      PanelToolTip {
        visible: chordHover.hovered
        text: "Kept bound in ~/.config/hypr/bindings.lua"
        fontFamily: view.host.fontFamily
      }
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
