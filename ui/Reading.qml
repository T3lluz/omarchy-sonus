import QtQuick
import qs.Commons
import qs.Commons as Commons

// A level as the panel prints it, the way Batteries does: the number big and
// bold, the percent sign half its size and dim on its baseline. Muted reads
// "Muted" instead, smaller so the width barely changes, centred on the
// digits' capitals.
Item {
  id: reading

  property real value: 0
  property bool muted: false
  property real size: Style.font.display
  property color color: Commons.Color.foreground
  property color dim: Qt.darker(color, 1.55)
  property string fontFamily: Style.font.family

  implicitWidth: muted ? word.implicitWidth : digits.implicitWidth
  implicitHeight: number.implicitHeight
  baselineOffset: number.baselineOffset

  Row {
    id: digits
    visible: !reading.muted
    anchors.right: parent.right
    spacing: Style.space(1)

    Text {
      id: number
      textFormat: Text.PlainText
      text: String(Math.round(reading.value * 100))
      color: reading.color
      font.family: reading.fontFamily
      font.pixelSize: reading.size
      font.bold: true
    }

    Text {
      anchors.baseline: number.baseline
      textFormat: Text.PlainText
      text: "%"
      color: reading.dim
      font.family: reading.fontFamily
      font.pixelSize: Math.round(reading.size * 0.5)
      font.bold: true
    }
  }

  Text {
    id: word
    visible: reading.muted
    anchors.right: parent.right
    // A capital is about 0.73 of the size, so half the difference in
    // capitals lifts the word to the digits' middle.
    y: number.baselineOffset - baselineOffset - (reading.size - font.pixelSize) * 0.365
    textFormat: Text.PlainText
    text: "Muted"
    color: reading.dim
    font.family: reading.fontFamily
    font.pixelSize: Math.round(reading.size * 0.6)
    font.bold: true
  }
}
