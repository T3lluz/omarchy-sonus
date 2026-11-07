import QtQuick
import qs.Commons
import qs.Commons as Commons

// The panel's title in one column of the top row, so what sits beside it fills
// the row instead of leaving it empty. The same parts as Omarchy's PanelHero:
// a 24 px icon, a bold title, and the changing caps caption. That one cuts its
// caption to one line; this one has the width of a tile, so the caption wraps.
Item {
  id: hero

  required property var host
  property string title: ""
  property string line: ""
  property real lineOpacity: 1
  property Component iconComponent: null
  default property alias actions: actionRow.children

  implicitHeight: Math.max(Style.font.display, labels.implicitHeight)

  // Measures two real lines of the caption, for the room it always keeps.
  Text {
    id: twoLines
    visible: false
    textFormat: Text.PlainText
    text: "X\nX"
    font.family: hero.host.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  Loader {
    id: iconLoader
    width: Style.font.display
    height: width
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    sourceComponent: hero.iconComponent
  }

  Column {
    id: labels
    anchors.left: iconLoader.right
    anchors.leftMargin: Style.space(10)
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(1)

    Item {
      width: parent.width
      height: Math.max(titleText.implicitHeight, actionRow.implicitHeight)

      Text {
        id: titleText
        anchors.left: parent.left
        anchors.right: actionRow.left
        anchors.rightMargin: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: hero.title
        color: hero.host.fg
        font.family: hero.host.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }

      Row {
        id: actionRow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)
      }
    }

    // Room for two lines always, so a caption wrapping as it changes does not
    // move everything below it.
    Text {
      width: parent.width
      height: Math.max(implicitHeight, twoLines.implicitHeight)
      wrapMode: Text.Wrap
      textFormat: Text.PlainText
      text: hero.line.toUpperCase()
      opacity: hero.lineOpacity
      color: Qt.darker(hero.host.fg, 1.4)
      font.family: hero.host.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
    }
  }
}
