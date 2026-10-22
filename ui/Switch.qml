import QtQuick

Item {
  id: sw

  required property var theme
  property bool checked: false
  property color tint: theme.accent
  signal toggled(bool value)

  implicitWidth: theme.s(38)
  implicitHeight: theme.s(22)

  Rectangle {
    anchors.fill: parent
    radius: height / 2
    color: sw.checked ? sw.tint : theme.track
    Behavior on color { ColorAnimation { duration: 140 } }
  }

  Rectangle {
    width: parent.height - theme.s(6)
    height: width
    radius: width / 2
    y: theme.s(3)
    x: sw.checked ? parent.width - width - theme.s(3) : theme.s(3)
    color: sw.checked ? theme.bg : theme.fg
    Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      sw.checked = !sw.checked
      sw.toggled(sw.checked)
    }
  }
}
