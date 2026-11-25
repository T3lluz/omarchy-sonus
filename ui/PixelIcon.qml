import QtQuick
import QtQuick.Window
import qs.Commons
import "Pixels.js" as Pixels
import "Motion.js" as Motion

// A pixel icon from Pixels.js, drawn as rectangles on whole device pixels so
// it stays sharp at any scale. The icon comes out as close to `size` as the
// grid allows: the 24-unit grid where a unit gets whole device pixels, the
// same grid halved (12 cells) where it would not. On a 1.25 scale a 14 px
// request draws 12 device pixels; a 20 px one draws 24.
// Never scaled: a fractional scale only ever picks the nearest sharp size.
//
// It also acts itself out (Motion.js): each time `play` goes up, and, drawn
// in from nothing, when `name` changes to an icon that moves. Moving, it
// draws its parts a whole stroke at a time; at rest, the plain art.
Item {
  id: icon

  property string name: ""
  // Art drawn elsewhere ({ g12, g24 }, as Pixels.js keeps it), in place of a
  // named icon: the Sonus mark, whose knobs move.
  property var custom: null
  property real size: 16
  property color color: "white"
  // Device pixels per cell of the halved grid, to match other pixel art
  // (PixelText) stroke for stroke; 0 picks it from `size`.
  property int unit: 0
  // Goes up each time the icon should act itself out, after `playDelay` ms.
  property int play: 0
  property int playDelay: 0
  // Rows of the microphone's capsule lit by what it hears (Motion.fillRows).
  property int fill: 0

  readonly property var art: custom || Pixels.icons[name] || null
  readonly property var spec: custom ? null : Motion.specFor(name)
  readonly property real dpr: Window.window && Window.window.devicePixelRatio > 0 ? Window.window.devicePixelRatio : 1
  // Device pixels across, in twelfths: odd counts take the halved grid. Its
  // strokes are this many device pixels thick either way.
  readonly property int twelfths: unit > 0 ? unit : Math.max(1, Math.round(size * dpr / 12))
  readonly property bool fine: twelfths % 2 === 0
  readonly property real cell: (fine ? twelfths / 2 : twelfths) / dpr

  // How far through its play, 1 at rest, and the frame that shows: whole
  // frames only, so the rectangles change a handful of times a play.
  property real t: 1
  property bool entering: false
  readonly property int frames: spec ? Math.max(1, Math.round(spec.ms / Motion.FRAME_MS)) : 1
  readonly property int frame: Math.min(frames, Math.floor(t * frames))
  readonly property bool moving: !!spec && frame < frames
  readonly property var rects: {
    if (!art) return []
    if (moving || fill > 0) return Motion.frame(art, spec, frame / frames, entering, fine, fill)
    return fine ? art.g24 : art.g12
  }

  property bool ready: false

  function start(fromNothing) {
    if (!spec || Style.reduceMotion) return
    // A play already under way finishes; only a change of state (drawn in
    // from nothing) cuts in, so hovering in and out does not stutter it.
    if (playRun.running && !fromNothing) return
    playRun.stop()
    entering = fromNothing
    t = 0
    playWait.duration = fromNothing ? 0 : Style.duration(playDelay)
    playRun.start()
  }

  onPlayChanged: start(false)
  onNameChanged: if (ready) start(true)
  Component.onCompleted: { ready = true; snap() }

  implicitWidth: twelfths * 12 / dpr
  implicitHeight: implicitWidth
  // A part may step out of the icon's square on its way in (the download
  // arrow); it never shows outside it.
  clip: moving

  SequentialAnimation {
    id: playRun
    PauseAnimation { id: playWait; duration: 0 }
    NumberAnimation {
      target: icon
      property: "t"
      from: 0
      to: 1
      duration: icon.spec ? Style.duration(icon.spec.ms) : 0
    }
  }

  // How far the cells move to start on a whole device pixel, checked after
  // each frame the window draws (it draws only when something changed). On a
  // 1.25 screen an icon at a fractional spot would smear its strokes.
  property real snapX: 0
  property real snapY: 0

  function snap() {
    if (!visible) return
    var p = icon.mapToItem(null, 0, 0)
    var dx = Math.round(p.x * dpr) / dpr - p.x
    var dy = Math.round(p.y * dpr) / dpr - p.y
    if (Math.abs(dx - snapX) > 0.001) snapX = dx
    if (Math.abs(dy - snapY) > 0.001) snapY = dy
  }

  Connections {
    target: icon.Window.window
    ignoreUnknownSignals: true
    function onAfterAnimating() { icon.snap() }
  }

  Item {
    x: icon.snapX
    y: icon.snapY
    width: icon.implicitWidth
    height: icon.implicitHeight

    // A count, not the list: a frame that keeps the number of rectangles
    // moves the ones there instead of building them again.
    Repeater {
      model: icon.rects.length

      Rectangle {
        required property int index
        readonly property var q: icon.rects[index] || [0, 0, 0, 0]
        x: Math.round(q[0] * icon.cell * icon.dpr) / icon.dpr
        y: Math.round(q[1] * icon.cell * icon.dpr) / icon.dpr
        width: Math.round(q[2] * icon.cell * icon.dpr) / icon.dpr
        height: Math.round(q[3] * icon.cell * icon.dpr) / icon.dpr
        color: icon.color
        antialiasing: false
      }
    }
  }
}
