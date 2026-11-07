import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Audio.js" as Audio
import "Glyphs.js" as Glyphs

// The output or the input in use, as one long line. The left part is the way
// to the other devices of its kind: clicking it opens DeviceList.
CursorSurface {
  id: tile

  required property var host
  required property string section
  required property string key
  required property string cursor
  property string role: ""
  property bool mic: false
  property bool metered: false
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
  readonly property bool keyed: host.cursorActive && host.cursorKey === cursor
  readonly property real level: fader.level
  readonly property bool sliding: fader.dragging

  implicitHeight: content.implicitHeight + host.tilePad * 2
  onKeyedChanged: if (keyed) host.ensureVisible(tile)

  hasCursor: keyed
  foreground: host.fg
  // Open, it only lifts a little: the one filled block on screen should be the
  // device in use, in the list below.
  color: hasCursor || listOpen ? fill : Style.normalFillFor(foreground, accent)

  HoverHandler {
    onHoveredChanged: if (hovered && tile.host.dragKey === "") tile.host.pointAt(tile.cursor)
  }

  WheelHandler {
    enabled: tile.channelPresent
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: function(event) { tile.host.wheelVolume(tile.key, event.angleDelta.y) }
  }

  // One long line: what it is on the left, how loud on the right.
  Item {
    id: content
    x: tile.host.tilePad
    y: tile.host.tilePad
    width: parent.width - x * 2
    height: parent.height - y * 2
    implicitHeight: Math.max(head.implicitHeight, fader.implicitHeight)

    Item {
      id: picker
      width: Math.round(parent.width * 0.53)
      height: head.implicitHeight
      anchors.verticalCenter: parent.verticalCenter

      Rectangle {
        anchors.fill: parent
        anchors.margins: -Style.space(2)
        radius: Style.cornerRadius
        visible: switchMouse.containsMouse
        color: Style.hoverFillFor(tile.host.fg, Commons.Color.accent)
      }

      TileHead {
        id: head
        width: parent.width
        host: tile.host
        icon: tile.device ? Glyphs.deviceGlyph(tile.device.form) : Glyphs.deviceGlyph(tile.section === "sink" ? "speaker" : "mic")
        title: tile.device ? tile.device.label : (tile.section === "sink" ? "No output" : "No input")
        line: tile.role
        dimmed: fader.muted || !tile.channelPresent

        Text {
          visible: tile.others > 0
          height: tile.host.iconCol
          verticalAlignment: Text.AlignVCenter
          textFormat: Text.PlainText
          text: tile.listOpen ? Glyphs.chevronUp : Glyphs.chevronDown
          color: switchMouse.containsMouse || tile.listOpen ? tile.host.fg : tile.host.dim
          font.family: tile.host.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      MouseArea {
        id: switchMouse
        anchors.fill: parent
        // Even with nothing left to pick (a Bluetooth device dropping out), an
        // open list can still be closed from here.
        enabled: tile.others > 0 || tile.listOpen
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: tile.host.toggleDevices(tile.section)
      }

      PanelToolTip {
        visible: switchMouse.containsMouse && !tile.listOpen
        text: "Switch " + tile.role.toLowerCase() + ": " + Audio.othersLine(tile.others, tile.section)
        fontFamily: tile.host.fontFamily
      }
    }

    TileFader {
      id: fader
      anchors.left: picker.right
      anchors.leftMargin: Style.space(6)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      host: tile.host
      key: tile.key
      name: tile.role.toLowerCase()
      mic: tile.mic
      present: tile.channelPresent
      metered: tile.metered
      reserveMeter: tile.host.hasInput
      peak: tile.peak
    }
  }
}
