import QtQuick
import qs.Commons
import "Model.js" as Model

// A room, after DailyDash's tiles: its tone washed over the panel, joined to
// the next by a small gap. When the panel opens the rooms rise into place one
// after another and each icon acts itself out. Pointing at a room presses the
// cells of its meters. A click ripples out from the pointer through them,
// plays the icon again and says `clicked`, which opens the room.
Rectangle {
  id: room

  required property var host
  property color tone: host.fg
  property var cells: []
  // How long after the panel opens this room comes in, in ms.
  property int delay: 0
  // Goes up each time the icon should act itself out.
  property int story: 0
  property bool expanded: false
  // The keyboard's cursor is on it: an outline as well as the tint, so it
  // reads apart from the pointer.
  property bool keyed: false
  // An app in the air would land here.
  property bool dropHot: false
  property bool clickable: true
  property real pad: host.roomPad
  property real spacing: Style.space(8)
  // What the content needs; a room that stretches part of its content to the
  // row's height sets this to its smallest.
  property real naturalHeight: inner.implicitHeight
  readonly property bool hovered: area.containsMouse
  property real rise: 0
  property real fade: 1
  default property alias content: inner.data

  signal clicked()

  width: parent ? parent.width : 0
  implicitHeight: naturalHeight + pad * 2
  radius: Style.cornerRadius
  color: Qt.rgba(tone.r, tone.g, tone.b, dropHot ? 0.17 : hovered || expanded || keyed ? 0.11 : 0.065)
  border.width: keyed || dropHot ? Math.max(1, Style.space(1)) : 0
  border.color: Qt.rgba(tone.r, tone.g, tone.b, 0.6)
  opacity: fade
  transform: Translate { y: room.rise }

  Behavior on color { ColorAnimation { duration: Style.duration(140) } }

  function enter() {
    riseIn.stop()
    if (Style.reduceMotion) { rise = 0; fade = 1; return }
    rise = Style.space(12)
    fade = 0
    riseIn.start()
  }

  Connections {
    target: room.host
    function onEntryChanged() { room.enter() }
  }

  SequentialAnimation {
    id: riseIn
    PauseAnimation { duration: Style.duration(room.delay) }
    ParallelAnimation {
      NumberAnimation { target: room; property: "rise"; to: 0; duration: Style.duration(460); easing.type: Easing.OutCubic }
      NumberAnimation { target: room; property: "fade"; to: 1; duration: Style.duration(280); easing.type: Easing.OutCubic }
    }
    ScriptAction { script: room.story++ }
  }

  // Under the content, so the faders and cards in a room take their own
  // clicks; hover reaches it all the same.
  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    enabled: room.clickable
    cursorShape: Qt.PointingHandCursor
    onPositionChanged: function(mouse) {
      for (var i = 0; i < room.cells.length; i++) {
        if (!room.cells[i]) continue
        var p = room.cells[i].mapFromItem(room, mouse.x, mouse.y)
        room.cells[i].hover(p.x, p.y)
      }
    }
    onExited: { for (var i = 0; i < room.cells.length; i++) if (room.cells[i]) room.cells[i].dent = null }
    onClicked: function(mouse) {
      // The clock first: a ripple is stamped with it.
      room.host.wake(Model.METER.RIPPLE_MS + 200)
      for (var i = 0; i < room.cells.length; i++) {
        if (!room.cells[i]) continue
        var p = room.cells[i].mapFromItem(room, mouse.x, mouse.y)
        room.cells[i].press(p.x, p.y)
      }
      room.story++
      room.clicked()
    }
  }

  Column {
    id: inner
    x: room.pad
    y: room.pad
    width: parent.width - room.pad * 2
    spacing: room.spacing
  }
}
