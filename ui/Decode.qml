import QtQuick
import qs.Commons
import "Model.js" as Model

// Text that decodes into place, a terminal's way, when the panel opens.
// Later changes just swap, so a line that changes stays easy to read. A
// MonoText, so it lands on whole device pixels; give it a step and family.
MonoText {
  id: dec

  required property var host
  property string value: ""
  property int delay: 0
  property real progress: 1
  property int seed: 0

  textFormat: Text.PlainText
  text: progress >= 1 ? value : Model.scramble(value, progress, seed)

  function run(wait) {
    decodeRun.stop()
    if (Style.reduceMotion) { progress = 1; return }
    seed = seed + 1
    decodeWait.duration = Style.duration(wait)
    progress = 0
    decodeRun.start()
  }

  Connections {
    target: dec.host
    function onEntryChanged() { dec.run(dec.delay) }
  }

  SequentialAnimation {
    id: decodeRun
    PauseAnimation { id: decodeWait; duration: 0 }
    NumberAnimation { target: dec; property: "progress"; to: 1; duration: Style.duration(Math.min(560, 180 + dec.value.length * 14)) }
  }
}
