import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Glyphs.js" as Glyphs

// The same control for a device, a channel and an app: a speaker that shows
// the level and mutes on click, the fader, the percent. The microphone also
// shows what it hears, under its fader, as Omarchy's audio panel does.
Item {
  id: fader

  required property var host
  required property string key
  // What the mute button's tooltip calls this thing.
  property string name: ""
  property bool present: true
  property bool mic: false
  property bool metered: false
  // Keeps the meter's room empty, so a fader beside a metered one lines up.
  property bool reserveMeter: false
  property real peak: 0

  readonly property var service: host.service
  readonly property bool muted: !!service && service.mutedOf(key)
  readonly property bool dragging: slider.dragging
  readonly property real level: slider.dragging ? slider.liveValue : (service ? service.volumeOf(key) : 0)

  function toggleMute() { if (service && present) service.setMute(key, !muted) }

  width: parent ? parent.width : implicitWidth
  implicitHeight: slider.implicitHeight + (metered || reserveMeter ? meter.height + Style.space(2) : 0)

  PanelActionButton {
    id: muteButton
    width: fader.host.iconCol
    height: width
    y: (slider.height - height) / 2
    enabled: fader.present
    iconText: fader.mic ? (fader.muted ? Glyphs.microphoneOff : Glyphs.microphone) : Glyphs.levelIcon(fader.muted, fader.level)
    tooltipText: (fader.muted ? "Unmute " : "Mute ") + fader.name + " (m)"
    foreground: fader.host.fg
    fontFamily: fader.host.fontFamily
    opacity: fader.muted ? 0.5 : 1
    onClicked: fader.toggleMute()
  }

  PanelSlider {
    id: slider
    bar: fader.host.bar
    anchors.left: muteButton.right
    anchors.leftMargin: Style.space(2)
    anchors.right: percent.left
    anchors.rightMargin: Style.space(2)
    minimum: 0
    maximum: 1
    step: 0.05
    // A muted level stays where it was, dimmed, so unmuting brings it back.
    value: fader.service ? fader.service.volumeOf(fader.key) : 0
    opacity: !fader.present || fader.muted ? 0.5 : 1
    enabled: fader.present
    onMoved: function(v) {
      if (fader.muted) fader.service.setMute(fader.key, false)
      fader.service.setVolume(fader.key, v)
    }
    onRightClicked: fader.toggleMute()
  }

  Text {
    id: percent
    anchors.right: parent.right
    y: (slider.height - height) / 2
    width: fader.host.percentW
    horizontalAlignment: Text.AlignRight
    textFormat: Text.PlainText
    text: Math.round(fader.level * 100) + "%"
    color: fader.host.dim
    opacity: fader.muted || !fader.present ? 0.5 : 1
    font.family: fader.host.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  Rectangle {
    id: meter
    visible: fader.metered
    x: slider.x + slider.knobSize / 2
    y: slider.height + Style.space(2)
    width: slider.width - slider.knobSize
    height: Math.max(Style.space(5), Style.spacing.xs)
    color: Qt.rgba(fader.host.fg.r, fader.host.fg.g, fader.host.fg.b, 0.18)
    opacity: fader.muted ? 0.35 : 1

    Rectangle {
      height: parent.height
      width: parent.width * Math.max(0, Math.min(1, fader.muted ? 0 : fader.peak))
      color: fader.host.fg
      Behavior on width { NumberAnimation { duration: Style.duration(70) } }
    }
  }
}
