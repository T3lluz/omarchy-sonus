import QtQuick
import "Glyphs.js" as Glyphs

// Settings card that slides in over the deck, like the EQ page.
Rectangle {
  id: drawer

  required property var theme
  property bool manageGraph: true
  property string versionText: ""
  property string updateState: "unknown"
  property bool updateBusy: false
  property bool updateApplying: false

  signal closeRequested()
  signal manageGraphToggled(bool value)
  signal updateClicked()

  radius: theme.cardRadius
  color: theme.mix(theme.bg, theme.fg, theme.light ? 0.045 : 0.04)
  border.width: Math.max(1, theme.s(1))
  border.color: theme.rule

  readonly property real pad: theme.s(16)
  readonly property string chipText: {
    if (updateBusy) return updateApplying ? "Updating…" : "Checking…"
    if (updateState === "current") return "Up to date"
    if (updateState === "outdated") return "Update"
    if (updateState === "failed") return "Retry"
    return "Check"
  }

  component Caption: Text {
    required property var theme
    color: theme.dim
    font.family: theme.font
    font.pixelSize: theme.s(10)
    font.weight: Font.Bold
    font.letterSpacing: theme.s(1)
  }

  component Note: Rectangle {
    id: note
    required property var theme
    property string text: ""
    property string code: ""
    width: parent.width
    height: noteColumn.implicitHeight + theme.s(22)
    radius: theme.chipRadius
    color: theme.card

    Column {
      id: noteColumn
      x: theme.s(12)
      y: theme.s(11)
      width: note.width - theme.s(24)
      spacing: theme.s(7)

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: note.text
        color: theme.dim
        font.family: theme.font
        font.pixelSize: theme.s(10)
        lineHeight: 1.15
      }

      Rectangle {
        visible: note.code !== ""
        width: parent.width
        height: codeText.implicitHeight + theme.s(10)
        radius: theme.s(4)
        color: theme.alpha(theme.fg, 0.06)

        Text {
          id: codeText
          x: theme.s(8)
          y: theme.s(5)
          width: parent.width - theme.s(16)
          wrapMode: Text.WrapAnywhere
          text: note.code
          color: theme.fg
          font.family: theme.font
          font.pixelSize: theme.s(10)
        }
      }
    }
  }

  // Blocks clicks from reaching the deck underneath.
  MouseArea { anchors.fill: parent; hoverEnabled: true }

  Rectangle {
    x: drawer.pad
    y: theme.s(23)
    width: theme.s(9)
    height: width
    radius: width / 2
    color: theme.accent
  }

  Text {
    x: drawer.pad + theme.s(18)
    y: theme.s(16)
    height: theme.s(22)
    verticalAlignment: Text.AlignVCenter
    text: "SETTINGS"
    color: theme.fg
    font.family: theme.font
    font.pixelSize: theme.s(13)
    font.weight: Font.Bold
    font.letterSpacing: theme.s(1)
  }

  IconButton {
    theme: drawer.theme
    glyph: Glyphs.close
    anchors.right: parent.right
    anchors.rightMargin: theme.s(10)
    y: theme.s(12)
    onClicked: drawer.closeRequested()
  }

  Flickable {
    x: drawer.pad
    y: theme.s(52)
    width: drawer.width - drawer.pad * 2
    height: updatesBlock.y - y - theme.s(10)
    contentHeight: flow.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    Column {
      id: flow
      width: parent.width
      spacing: theme.s(8)

      Caption { theme: drawer.theme; text: "GENERAL" }

      Rectangle {
        width: parent.width
        height: Math.max(theme.s(58), rowText.implicitHeight + theme.s(22))
        radius: theme.chipRadius
        color: theme.card

        Column {
          id: rowText
          x: theme.s(12)
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - theme.s(24) - graphSwitch.width - theme.s(10)
          spacing: theme.s(3)

          Text {
            text: "Virtual channels"
            color: theme.fg
            font.family: theme.font
            font.pixelSize: theme.s(11)
            font.weight: Font.DemiBold
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Provide Game, Chat, Media and Aux devices."
            color: theme.dim
            font.family: theme.font
            font.pixelSize: theme.s(10)
          }
        }

        Switch {
          id: graphSwitch
          theme: drawer.theme
          anchors.right: parent.right
          anchors.rightMargin: theme.s(12)
          anchors.verticalCenter: parent.verticalCenter
          checked: drawer.manageGraph
          onToggled: function(value) { drawer.manageGraphToggled(value) }
        }
      }

      Item { width: 1; height: theme.s(4) }
      Caption { theme: drawer.theme; text: "SHORTCUT" }

      Note {
        theme: drawer.theme
        text: "Ctrl+Alt+V shows or hides the panel. To bind it, add this to ~/.config/hypr/bindings.lua:"
        code: "o.bind(\"CTRL + ALT + V\", \"Sonus\", \"omarchy-shell sonus toggle\")"
      }

      Item { width: 1; height: theme.s(4) }
      Caption { theme: drawer.theme; text: "EQUALIZER" }

      Note {
        theme: drawer.theme
        text: "The sliders icon on a category opens its 10-band EQ. EasyEffects stays a post-mix slot and its own equalizer is kept off, so the two never stack."
      }
    }
  }

  Column {
    id: updatesBlock
    x: drawer.pad
    y: drawer.height - height - theme.s(14)
    width: drawer.width - drawer.pad * 2
    spacing: theme.s(8)

    Caption { theme: drawer.theme; text: "UPDATES" }

    Rectangle {
      width: parent.width
      height: theme.s(44)
      radius: theme.chipRadius
      color: theme.card

      Text {
        x: theme.s(12)
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - updateChip.width - theme.s(34)
        elide: Text.ElideRight
        text: drawer.versionText
        color: theme.dim
        font.family: theme.font
        font.pixelSize: theme.s(10)
      }

      Chip {
        id: updateChip
        theme: drawer.theme
        anchors.right: parent.right
        anchors.rightMargin: theme.s(8)
        anchors.verticalCenter: parent.verticalCenter
        text: drawer.chipText
        active: drawer.updateState === "outdated" && !drawer.updateBusy
        enabled_: !drawer.updateBusy
        onClicked: drawer.updateClicked()
      }
    }
  }
}
