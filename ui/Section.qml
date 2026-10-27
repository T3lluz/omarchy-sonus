import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// One section of the mixer: a separator, a header with an optional reading on
// the right, then the rows passed in at the call site. A section with a `key`
// is also a drop target; `hot` lights it while an app hovers over it.
//
// The chrome is assigned to `data` explicitly: with `content` as the default
// property, children declared here would land in `inner` too.
Column {
  id: section

  default property alias content: inner.data
  property string title: ""
  property string meta: ""
  property string key: ""
  property bool hot: false
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family

  spacing: Style.space(6)

  data: [
    PanelSeparator {
      foreground: section.foreground
    },

    Item {
      visible: section.title !== ""
      width: section.width
      implicitHeight: Math.max(header.implicitHeight, metaText.implicitHeight)

      PanelSectionHeader {
        id: header
        text: section.title
        foreground: section.foreground
        fontFamily: section.fontFamily
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: metaText
        visible: section.meta !== ""
        textFormat: Text.PlainText
        text: section.meta
        color: Qt.darker(section.foreground, 1.4)
        font.family: section.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
      }
    },

    Item {
      width: section.width
      implicitHeight: inner.implicitHeight
      height: implicitHeight

      // The drop highlight sits behind the rows, not the header.
      CursorSurface {
        anchors.fill: parent
        anchors.margins: -Style.space(3)
        visible: section.hot
        current: true
        foreground: section.foreground
      }

      Column {
        id: inner
        width: parent.width
        spacing: Style.space(2)
      }
    }
  ]
}
