import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model
import "Motion.js" as Motion

// The same control for a device, a channel and an app: the mute button in the
// room's icon column, a pixel icon that shows the level, then the meter of
// cells that is also the fader. A muted level stays where it was, dimmed, so
// unmuting brings it back.
Item {
  id: fader

  required property var host
  required property string key
  // What the mute button's tooltip calls this thing.
  property string name: ""
  property bool present: true
  property bool mic: false
  property color tone: host.fg
  property bool small: false
  property int delay: 0
  property real peak: 0
  // The mute button's column, and the gap after it: a room's icon column, so
  // the meter starts under the room's name.
  property real column: host.iconColumn
  property real columnGap: Style.space(10)

  readonly property var service: host.service
  readonly property bool muted: !!service && service.mutedOf(key)
  readonly property real level: service ? service.volumeOf(key) : 0
  readonly property alias meter: bar
  readonly property bool dragging: bar.dragging
  // What the meter shows, 0..100, for the figure to count along with.
  readonly property real shown: bar.shown

  function toggleMute() { if (service && present) service.setMute(key, !muted) }

  width: parent ? parent.width : implicitWidth
  implicitHeight: Math.max(bar.implicitHeight, muteButton.height)

  Item {
    id: muteButton
    width: fader.column
    height: Math.max(bar.implicitHeight, icon.implicitHeight + Style.space(4))
    anchors.verticalCenter: parent.verticalCenter
    opacity: fader.present ? 1 : 0.45

    Rectangle {
      anchors.centerIn: parent
      width: parent.width + Style.space(4)
      height: parent.height + Style.space(2)
      radius: Style.cornerRadius
      visible: muteMouse.containsMouse
      color: Qt.rgba(fader.tone.r, fader.tone.g, fader.tone.b, 0.16)
    }

    PixelIcon {
      id: icon
      x: Math.round((parent.width - width) / 2)
      y: Math.round((parent.height - height) / 2)
      name: Model.levelPixel(fader.muted, fader.level, fader.mic)
      size: fader.small ? Style.font.bodySmall : Style.font.title
      color: fader.muted ? fader.host.dim : fader.tone
      // Pointing at it plays it: the waves ripple, the capsule lifts. A
      // microphone that hears something fills its capsule to the level.
      play: muteMouse.hovers
      fill: fader.mic && !fader.muted && !Style.reduceMotion ? Motion.fillRows(fader.peak) : 0
    }

    MouseArea {
      id: muteMouse
      property int hovers: 0
      anchors.fill: parent
      enabled: fader.present
      hoverEnabled: true
      onEntered: hovers++
      cursorShape: Qt.PointingHandCursor
      onClicked: fader.toggleMute()
    }

    PanelToolTip {
      visible: muteMouse.containsMouse
      text: (fader.muted ? "Unmute " : "Mute ") + fader.name + " (m)"
      fontFamily: fader.host.fontFamily
    }
  }

  Meter {
    id: bar
    host: fader.host
    anchors.left: muteButton.right
    anchors.leftMargin: fader.columnGap
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    small: fader.small
    level: fader.present ? Model.percentOf(fader.level) : 0
    known: fader.present
    dimmed: fader.muted
    interactive: fader.present
    peak: fader.peak
    tone: fader.tone
    foreground: fader.host.fg
    delay: fader.delay
    onMoved: function(v) {
      if (!fader.service) return
      if (fader.muted) fader.service.setMute(fader.key, false)
      fader.service.setVolume(fader.key, v)
    }
    onRightClicked: fader.toggleMute()

    // When the mixer scrolls, the rooms leave the wheel to it; over the
    // meter itself the wheel still sets the level.
    WheelHandler {
      enabled: fader.present && !!fader.host.mixerScrolls
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
      onWheel: function(event) { fader.host.wheelVolume(fader.key, event.angleDelta.y) }
    }
  }
}
