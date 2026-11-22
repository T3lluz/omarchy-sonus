import QtQuick
import qs.Commons
import "Model.js" as Model

// The Sonus mark (Model.sonusLogo): three faders, each track lit under its
// knob and dim over it, as on the app icon. Muted, the faders are down and
// all of it dim. With `animated`, the knobs move to where they are going a
// row at a time: up into place when `play()` is called (the panel opening),
// down and back when the output is muted and unmuted.
Item {
  id: logo

  property real size: 16
  // Device pixels per cell, as PixelIcon.unit; 0 picks it from `size`.
  property int unit: 0
  property color color: "white"
  property color dimColor: Qt.darker(color, 1.6)
  property bool muted: false
  property bool animated: false

  readonly property var target: muted ? Model.LOGO_DOWN : Model.LOGO_KNOBS
  // Where the knobs start from and how far along they are; at rest, `k` is 1
  // and the knobs are on `target`.
  property var from: Model.LOGO_KNOBS
  property var settled: null
  property real k: 1
  readonly property var knobs: Model.logoKnobs(from, target, k)

  implicitWidth: lit.implicitWidth
  implicitHeight: lit.implicitHeight

  Component.onCompleted: { settled = target; from = target }

  // From the faders down, as the panel opens.
  function play() {
    if (!animated || Style.reduceMotion) return
    from = Model.LOGO_DOWN
    run.restart()
  }

  // Muting slides the faders down from wherever they are, unmuting back up.
  onTargetChanged: {
    var start = settled === null ? target : run.running ? Model.logoKnobs(from, settled, k) : settled
    settled = target
    if (!animated || Style.reduceMotion) { run.stop(); from = target; k = 1; return }
    from = start
    run.restart()
  }

  NumberAnimation {
    id: run
    target: logo
    property: "k"
    from: 0
    to: 1
    duration: Style.duration(620)
  }

  PixelIcon {
    custom: Model.sonusLogo(logo.knobs, "track")
    size: logo.size
    unit: logo.unit
    color: logo.dimColor
  }

  PixelIcon {
    id: lit
    custom: Model.sonusLogo(logo.knobs, "lit")
    size: logo.size
    unit: logo.unit
    color: logo.muted ? logo.dimColor : logo.color
  }
}
