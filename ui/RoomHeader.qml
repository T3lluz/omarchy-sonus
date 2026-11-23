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
  // The icon's story (Model.storyOf) and a count that plays it each time it
  // goes up.
  property string story: "pop"
  property int tick: 0
  property real k: 1
  readonly property var pose: Model.storyPose(story, k)
  readonly property alias iconItem: iconBox

  width: parent ? parent.width : 0
  implicitHeight: Math.max(labels.implicitHeight, showFigure ? figure.implicitHeight : 0, iconBox.height)

  onTickChanged: if (!Style.reduceMotion) storyRun.restart()

  NumberAnimation {
    id: storyRun
    target: head
    property: "k"
    from: 0
    to: 1
    duration: Style.duration(head.story === "buzz" ? 520 : 660)
  }

  // Moves in whole pixels of its own grid, so it never smears.
  PixelIcon {
    id: iconBox
    x: Math.round((head.host.iconColumn - width) / 2)
    y: Math.round((head.height - height) / 2)
    name: head.icon
    size: head.host.iconColumn
    color: head.dimmed ? head.host.dim : head.tone
    transform: Translate { x: head.pose.x * iconBox.cell; y: head.pose.y * iconBox.cell }
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
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        text: head.title
        color: head.dimmed ? head.host.dim : head.host.fg
        font.family: head.host.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
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
        visible: head.showChevron
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
      font.pixelSize: Style.font.caption
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
    // The block face is measured on the shell's font, not the panel's
    // Monocraft, so the digits keep their size.
    fontFamily: head.host.shellFont
  }
}
