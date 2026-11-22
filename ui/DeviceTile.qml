import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Audio.js" as Audio
import "Model.js" as Model

// The output or the input in use, as a room: the device's icon, its name and
// how many others there are, the volume in the block face, and the meter that
// is its fader. A click opens the other devices of its kind (DeviceList,
// under the top row) to switch to.
Room {
  id: tile

  required property string section
  required property string key
  required property string cursor
  property string role: ""
  property bool mic: false
  property real peak: 0

  readonly property var service: host.service
  readonly property var devices: host.devices(section)
  readonly property var device: {
    for (var i = 0; i < devices.length; i++) if (devices[i] && devices[i].active) return devices[i]
    return null
  }
  readonly property int others: devices.filter(function(d) { return d && d.name && !d.active }).length
  readonly property bool listOpen: host.devicesOpen(section)
  readonly property bool channelPresent: !!(service && service.channels && service.channels[key])
  readonly property real level: fader.level
  readonly property bool sliding: fader.dragging

  tone: host.toneFor(key)
  cells: [fader.meter]
  expanded: listOpen
  keyed: host.cursorActive && host.cursorKey === cursor
  onKeyedChanged: if (keyed) host.ensureVisible(tile)
  onClicked: tile.host.toggleDevices(tile.section)

  HoverHandler {
    onHoveredChanged: if (hovered && tile.host.dragKey === "") tile.host.pointAt(tile.cursor)
  }

  WheelHandler {
    enabled: tile.channelPresent
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: function(event) { tile.host.wheelVolume(tile.key, event.angleDelta.y) }
  }

  RoomHeader {
    id: head
    host: tile.host
    icon: Model.devicePixel(tile.device ? tile.device.form : "", tile.section)
    tone: tile.tone
    title: tile.device ? tile.device.label : (tile.section === "sink" ? "No output" : "No input")
    status: Audio.deviceState(tile.role, fader.muted, tile.others, tile.section)
    value: tile.channelPresent ? fader.shown : null
    mark: Model.markFor(fader.muted, tile.mic, false)
    figureDimmed: fader.muted
    dimmed: !tile.channelPresent
    showChevron: tile.others > 0 || tile.listOpen
    expanded: tile.listOpen
    story: Model.storyOf(tile.device ? tile.device.form : tile.section === "src" ? "mic" : "speaker")
    tick: tile.story
    delay: tile.delay + 120

    HoverHandler { id: headHover }

    PanelToolTip {
      visible: headHover.hovered && !tile.listOpen && tile.others > 0
      text: "Switch " + tile.role.toLowerCase() + ": " + Audio.othersLine(tile.others, tile.section)
      fontFamily: tile.host.fontFamily
    }
  }

  Fader {
    id: fader
    host: tile.host
    key: tile.key
    name: tile.role.toLowerCase()
    mic: tile.mic
    present: tile.channelPresent
    tone: tile.tone
    peak: tile.peak
    delay: tile.delay + 80
  }
}
