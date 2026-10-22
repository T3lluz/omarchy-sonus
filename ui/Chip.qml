import QtQuick

// Rounded text button: presets, Back, Reset, Update.
Rectangle {
  id: chip

  required property var theme
  property string text: ""
  property string glyph: ""
  property color tint: theme.fg
  property bool active: false
  property bool enabled_: true
  signal clicked()

  implicitWidth: row.implicitWidth + theme.s(24)
  implicitHeight: theme.s(28)
  radius: theme.chipRadius
  color: active ? theme.alpha(tint, 0.2)
    : (mouse.containsMouse && enabled_ ? theme.buttonHover : theme.buttonFill)
  border.width: active ? Math.max(1, theme.s(1)) : 0
  border.color: theme.alpha(tint, 0.65)
  opacity: enabled_ ? 1 : 0.55

  Behavior on color { ColorAnimation { duration: 120 } }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: theme.s(6)

    Text {
      visible: chip.glyph !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: chip.glyph
      color: chip.active ? chip.tint : theme.fg
      font.family: theme.font
      font.pixelSize: theme.s(13)
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: chip.text
      textFormat: Text.PlainText
      color: chip.active ? chip.tint : theme.fg
      font.family: theme.font
      font.pixelSize: theme.s(11)
      font.weight: Font.DemiBold
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: chip.enabled_ ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: if (chip.enabled_) chip.clicked()
  }
}
