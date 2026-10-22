import QtQuick

// Square glyph button for the header: settings, close.
Rectangle {
  id: button

  required property var theme
  property string glyph: ""
  property bool danger: false
  property bool badge: false
  property bool active: false
  property string tip: ""
  signal clicked()

  implicitWidth: theme.s(30)
  implicitHeight: theme.s(30)
  radius: theme.chipRadius
  color: mouse.containsMouse
    ? (danger ? theme.alpha(theme.urgent, 0.28) : theme.buttonHover)
    : (active ? theme.buttonHover : "transparent")
  Behavior on color { ColorAnimation { duration: 120 } }

  Text {
    anchors.centerIn: parent
    text: button.glyph
    color: mouse.containsMouse && button.danger ? theme.mix(theme.urgent, theme.fg, 0.35) : theme.fg
    font.family: theme.font
    font.pixelSize: theme.s(16)
  }

  Rectangle {
    visible: button.badge
    width: theme.s(8)
    height: width
    radius: width / 2
    color: theme.accent
    border.width: Math.max(1, theme.s(1.5))
    border.color: theme.bg
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.margins: theme.s(4)
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: button.clicked()
  }
}
