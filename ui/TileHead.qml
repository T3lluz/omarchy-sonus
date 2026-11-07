import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The top of every tile and app: an icon in the column the mute button sits
// under, a name, a line that says what is going on, and any buttons on the
// right. Names wrap rather than cut.
Item {
  id: head

  required property var host
  property string icon: ""
  property string title: ""
  property string line: ""
  // What this thing is, for anyone who wonders: on the icon, so no words have
  // to sit in the panel for it.
  property string iconTip: ""
  property bool dimmed: false
  default property alias actions: actionRow.children

  width: parent ? parent.width : implicitWidth
  implicitHeight: Math.max(host.iconCol, labels.implicitHeight)

  Text {
    id: glyph
    width: head.host.iconCol
    height: head.host.iconCol
    anchors.verticalCenter: parent.verticalCenter
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    textFormat: Text.PlainText
    text: head.icon
    color: head.host.fg
    opacity: head.dimmed ? 0.5 : 1
    font.family: head.host.fontFamily
    font.pixelSize: Style.font.heading

    HoverHandler { id: iconHover }

    PanelToolTip {
      visible: iconHover.hovered && head.iconTip !== ""
      text: head.iconTip
      fontFamily: head.host.fontFamily
    }
  }

  Column {
    id: labels
    anchors.left: glyph.right
    anchors.leftMargin: Style.space(4)
    anchors.right: actionRow.left
    anchors.rightMargin: actionRow.children.length > 0 ? Style.space(2) : 0
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(1)

    Text {
      width: parent.width
      wrapMode: Text.Wrap
      textFormat: Text.PlainText
      text: head.title
      color: head.dimmed ? head.host.dim : head.host.fg
      font.family: head.host.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }

    Text {
      width: parent.width
      visible: text !== ""
      wrapMode: Text.Wrap
      textFormat: Text.PlainText
      text: head.line
      color: head.host.dim
      font.family: head.host.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Row {
    id: actionRow
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)
  }
}
