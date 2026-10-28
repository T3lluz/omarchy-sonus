import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// One section of the mixer: a separator, the panel kit's section header with
// an optional reading on the right, then the rows passed in at the call site.
// A section with a `key` is also a drop target; `hot` lights it while an app
// hovers over it.
//
// The chrome is assigned to `data` explicitly: with `content` as the default
// property, children declared here would land in `inner` too.
Column {
  id: section

  default property alias content: inner.data
  property string icon: ""
  property string title: ""
  property string meta: ""
  property string key: ""
  property bool hot: false
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family

  spacing: Style.space(12)

  data: [
    PanelSeparator {
      foreground: section.foreground
    },

    SectionHeader {
      visible: section.title !== ""
      width: section.width
      icon: section.icon
      title: section.title
      detail: section.meta.toUpperCase()
      foreground: section.foreground
      fontFamily: section.fontFamily
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
