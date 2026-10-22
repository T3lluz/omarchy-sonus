import QtQuick
import "Glyphs.js" as Glyphs

// The click-and-pick alternative to dragging an app onto a bin.
Rectangle {
  id: menu

  required property var theme
  property string appName: ""
  property string current: ""
  property bool effectsRunning: false
  property var categories: []
  signal picked(string channel)

  width: theme.s(226)
  height: column.implicitHeight + theme.s(12)
  radius: theme.cardRadius
  color: theme.mix(theme.bg, theme.fg, theme.light ? 0.03 : 0.07)
  border.width: Math.max(1, theme.s(1))
  border.color: theme.alpha(theme.fg, 0.16)

  component Item_: Rectangle {
    id: row
    required property var theme
    property string text: ""
    property color dot: "transparent"
    property bool checked: false
    signal activated()
    height: theme.s(30)
    radius: theme.chipRadius
    color: rowMouse.containsMouse ? theme.buttonHover : "transparent"

    Rectangle {
      x: theme.s(10)
      anchors.verticalCenter: parent.verticalCenter
      width: theme.s(8)
      height: width
      radius: width / 2
      color: row.dot
    }

    Text {
      x: theme.s(26)
      anchors.verticalCenter: parent.verticalCenter
      text: row.text
      color: theme.fg
      font.family: theme.font
      font.pixelSize: theme.s(11)
    }

    Text {
      visible: row.checked
      anchors.right: parent.right
      anchors.rightMargin: theme.s(10)
      anchors.verticalCenter: parent.verticalCenter
      text: Glyphs.check
      color: row.dot
      font.family: theme.font
      font.pixelSize: theme.s(13)
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: row.activated()
    }
  }

  Column {
    id: column
    x: theme.s(6)
    y: theme.s(6)
    width: menu.width - theme.s(12)
    spacing: theme.s(1)

    Text {
      width: parent.width
      leftPadding: theme.s(10)
      topPadding: theme.s(4)
      bottomPadding: theme.s(6)
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: menu.appName
      color: theme.dim
      font.family: theme.font
      font.pixelSize: theme.s(10)
      font.weight: Font.Bold
    }

    Repeater {
      model: menu.categories

      Item_ {
        required property var modelData
        theme: menu.theme
        width: column.width
        text: "Send to " + modelData.title
        dot: modelData.color
        checked: menu.current === modelData.key
        onActivated: menu.picked(modelData.key)
      }
    }

    Rectangle {
      width: parent.width
      height: theme.s(9)
      color: "transparent"
      Rectangle {
        anchors.centerIn: parent
        width: parent.width - theme.s(12)
        height: Math.max(1, theme.s(1))
        color: theme.rule
      }
    }

    Item_ {
      theme: menu.theme
      width: column.width
      text: menu.effectsRunning ? "Send to output (EasyEffects)" : "Send to output"
      dot: theme.dim
      checked: menu.current === ""
      onActivated: menu.picked("")
    }
  }
}
