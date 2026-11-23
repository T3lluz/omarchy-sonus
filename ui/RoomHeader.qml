import QtQuick
import qs.Commons
import "Model.js" as Model

// A room's first line: its pixel icon, the name over a line of state, and
// the volume in the block face on the right. The chevron by the name says
// the room opens.
Item {
  id: head

  required property var host
  property string icon: ""
  property color tone: host.fg
  property string title: ""
  property string status: ""
  property bool showFigure: true
  property var value: null
  property string mark: ""
  property bool figureDimmed: false
  property bool showChevron: true
  property bool expanded: false
  property bool dimmed: false
  property int delay: 0
  // Goes up each time the icon should act itself out (Motion.js).
  property int tick: 0
  readonly property alias iconItem: iconBox

  width: parent ? parent.width : 0
  implicitHeight: Math.max(labels.implicitHeight, showFigure ? figure.implicitHeight : 0, iconBox.height)

  // What the name's column needs so that no word in it breaks: its longest
  // word, with the chevron after it. The figure gives up room to keep that.
  readonly property string longestWord: title.split(/\s+/).reduce(function(a, b) { return b.length > a.length ? b : a }, "")
  readonly property real titleNeed: Math.ceil(wordMetrics.advanceWidth) + Style.space(1)
    + (showChevron ? chevron.implicitWidth + Style.space(5) : 0)
  // Too narrow even with the smallest figure (a very small screen): the
  // chevron steps aside to give the name its room.
  readonly property bool cramped: labels.width + 0.5 < titleNeed

  TextMetrics {
    id: wordMetrics
    font.family: head.host.fontFamily
    font.pixelSize: head.host.textSize
    text: head.longestWord
  }

  PixelIcon {
    id: iconBox
    x: Math.round((head.host.iconColumn - width) / 2)
    y: Math.round((head.height - height) / 2)
    name: head.icon
    size: head.host.iconColumn
    color: head.dimmed ? head.host.dim : head.tone
    play: head.tick
  }

  Column {
    id: labels
    anchors.left: parent.left
    anchors.leftMargin: head.host.textInset
    anchors.right: head.showFigure ? figure.left : parent.right
    anchors.rightMargin: head.showFigure ? Style.space(8) : 0
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(1)

    // The name, wrapping when it must, with the chevron after its last line.
    Item {
      width: parent.width
      height: titleText.height

      Text {
        id: titleText
        readonly property real room: chevron.visible ? chevron.width + Style.space(5) : 0
        property real lastRight: 0
        property real lastY: 0
        property real lastHeight: 0
        width: Math.min(implicitWidth, parent.width - room)
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        text: Model.wrapName(head.title, Model.monoColumns(parent.width - room, head.host.textSize))
        color: head.dimmed ? head.host.dim : head.host.fg
        font.family: head.host.fontFamily
        font.pixelSize: head.host.textSize
        renderType: Text.NativeRendering
        onLineLaidOut: function(line) {
          if (!line.isLast) return
          lastRight = line.x + line.implicitWidth
          lastY = line.y
          lastHeight = line.height
        }
      }

      // Flips when the room opens; turned pixel art would smear on the way.
      PixelIcon {
        id: chevron
        visible: head.showChevron && !head.cramped
        x: Math.round(titleText.lastRight + Style.space(5))
        y: Math.round(titleText.lastY + (titleText.lastHeight - height) / 2)
        name: "chevron-down"
        size: Style.font.caption
        color: head.host.dim
        rotation: head.expanded ? 180 : 0
      }
    }

    Decode {
      host: head.host
      width: parent.width
      visible: value !== ""
      wrapMode: Text.Wrap
      value: head.status
      delay: head.delay
      color: head.host.dim
      font.family: head.host.fontFamily
      font.pixelSize: head.host.textSize
      renderType: Text.NativeRendering
    }
  }

  BigFigure {
    id: figure
    visible: head.showFigure
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    value: head.value
    tone: head.tone
    foreground: head.host.fg
    mark: head.mark
    dimmed: head.figureDimmed
    // The mark acts itself out a beat after the room's icon.
    markPlay: head.tick
    // The block face is measured on the shell's font, not the panel's
    // Monocraft, so the digits keep their size.
    fontFamily: head.host.shellFont
    maxWidth: head.width - head.host.textInset - Style.space(8) - head.titleNeed
  }
}
