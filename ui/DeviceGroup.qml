import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Audio.js" as Audio
import "Glyphs.js" as Glyphs

// The output or the input in use, on the panel's grid: icon, name over what
// it is, fader, level. Clicking the icon mutes; the name opens the other
// devices of its kind, and clicking one switches to it.
Item {
  id: group

  required property var host
  required property string section
  required property string key
  required property string cursor
  property string role: ""
  // The input shows what the microphone hears under its fader.
  property bool metered: false
  property real peak: 0

  readonly property var service: host.service
  readonly property var devices: host.devices(section)
  readonly property var device: {
    for (var i = 0; i < devices.length; i++) if (devices[i] && devices[i].active) return devices[i]
    return null
  }
  readonly property var others: devices.filter(function(d) { return d && d.name && !d.active })
  readonly property bool open: host.devicesOpen(section) && others.length > 0
  readonly property bool present: !!(service && service.channels && service.channels[key])
  readonly property bool muted: !!service && service.mutedOf(key)
  readonly property real level: fader.dragging ? fader.liveValue : (service ? service.volumeOf(key) : 0)
  readonly property bool hasCursor: host.cursorActive && host.cursorKey === cursor

  width: parent ? parent.width : 0
  implicitHeight: open ? list.y + list.height : row.height
  height: implicitHeight
  onHasCursorChanged: if (hasCursor) host.ensureVisible(row)

  function toggleMute() { if (service && present) service.setMute(key, !muted) }

  Item {
    id: row
    width: parent.width
    height: Math.max(lines.implicitHeight, fader.height) + Style.space(12)

    CursorSurface {
      anchors.fill: parent
      hasCursor: group.hasCursor
      foreground: group.host.fg
    }

    HoverHandler {
      onHoveredChanged: if (hovered && group.host.dragKey === "") group.host.pointAt(group.cursor)
    }

    WheelHandler {
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
      onWheel: function(event) { group.host.wheelVolume(group.key, event.angleDelta.y) }
    }

    Art {
      x: group.host.rowPad
      anchors.verticalCenter: parent.verticalCenter
      width: group.host.iconW
      height: group.host.iconH
      name: Audio.drawingFor(group.device ? group.device.form : (group.section === "sink" ? "speaker" : "mic"),
        group.device ? group.device.label : "")
      color: group.host.fg
      opacity: group.muted || !group.present ? 0.4 : 1

      MouseArea {
        id: artMouse
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        hoverEnabled: true
        cursorShape: group.present ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: group.toggleMute()
      }

      PanelToolTip {
        visible: artMouse.containsMouse && group.present
        text: (group.muted ? "Unmute " : "Mute ") + group.role.toLowerCase() + " (m)"
        fontFamily: group.host.fontFamily
      }
    }

    Column {
      id: lines
      x: group.host.nameX
      width: group.host.nameW
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)

      // A no-break space keeps the chevron on the name's last word, so a long
      // name wraps without leaving it alone on a line.
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        textFormat: Text.StyledText
        text: {
          var label = Audio.escapeHtml(group.device ? group.device.label : (group.section === "sink" ? "No output" : "No input"))
          if (group.others.length === 0) return label
          var tone = nameMouse.containsMouse || group.open ? group.host.fg : group.host.dim
          return label + "&nbsp;<font color=\"" + tone + "\">" + (group.open ? Glyphs.chevronUp : Glyphs.chevronDown) + "</font>"
        }
        color: group.host.fg
        font.family: group.host.fontFamily
        font.pixelSize: Style.font.subtitle

        MouseArea {
          id: nameMouse
          anchors.fill: parent
          visible: group.others.length > 0
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: group.host.toggleDevices(group.section)
        }

        PanelToolTip {
          visible: nameMouse.containsMouse && !group.open
          text: "Switch " + group.role.toLowerCase() + ": " + Audio.othersLine(group.others.length, group.section)
          fontFamily: group.host.fontFamily
        }
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: group.role
        color: group.host.dim
        font.family: group.host.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    PanelSlider {
      id: fader
      bar: group.host.bar
      x: group.host.faderX
      width: group.host.faderWidth(row.width)
      anchors.verticalCenter: parent.verticalCenter
      minimum: 0
      maximum: 1
      step: 0.05
      // A muted level stays where it was, dimmed, so unmuting brings it back.
      value: group.service ? group.service.volumeOf(group.key) : 0
      opacity: !group.present || group.muted ? 0.4 : 1
      enabled: group.present
      onMoved: function(v) {
        if (group.muted) group.service.setMute(group.key, false)
        group.service.setVolume(group.key, v)
      }
      onRightClicked: group.toggleMute()
    }

    // What the microphone hears right now, a hairline under its fader. The
    // one thing in the panel that moves on its own.
    Rectangle {
      visible: group.metered
      x: fader.x + fader.knobSize / 2
      y: fader.y + fader.height / 2 + fader.knobSize / 2 + Style.space(2)
      width: fader.width - fader.knobSize
      height: Math.max(2, Style.space(2))
      radius: height / 2
      color: Qt.rgba(group.host.fg.r, group.host.fg.g, group.host.fg.b, 0.1)

      Rectangle {
        height: parent.height
        radius: parent.radius
        width: parent.width * Math.max(0, Math.min(1, group.muted ? 0 : group.peak))
        color: group.host.dim
        Behavior on width { NumberAnimation { duration: 70 } }
      }
    }

    Reading {
      anchors.right: parent.right
      anchors.rightMargin: group.host.rowPad
      anchors.verticalCenter: parent.verticalCenter
      value: group.level
      muted: group.muted
      size: group.host.readingSize
      color: group.present ? group.host.fg : group.host.dim
      dim: group.host.dim
      fontFamily: group.host.fontFamily
    }
  }

  // The other devices of this kind, under the name. Pointing at one lights it.
  Column {
    id: list
    visible: group.open
    y: row.height + Style.space(2)
    width: parent.width

    Repeater {
      model: group.open ? group.others : []

      Item {
        id: pick
        required property var modelData
        readonly property string pickKey: group.section + ":" + modelData.name
        readonly property bool keyed: group.host.cursorActive && group.host.cursorKey === pickKey
        readonly property bool lit: pickMouse.containsMouse || keyed

        width: list.width
        height: Math.max(pickName.implicitHeight, group.host.iconH) + Style.space(12)
        onKeyedChanged: if (keyed) group.host.ensureVisible(pick)

        CursorSurface {
          anchors.fill: parent
          hasCursor: pick.lit
          foreground: group.host.fg
        }

        Art {
          x: group.host.rowPad
          anchors.verticalCenter: parent.verticalCenter
          width: group.host.iconW
          height: group.host.iconH
          name: Audio.drawingFor(pick.modelData.form, pick.modelData.label)
          color: pick.lit ? group.host.fg : group.host.dim
        }

        Text {
          id: pickName
          x: group.host.nameX
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - x - group.host.rowPad
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          text: pick.modelData.label || "Unknown"
          color: pick.lit ? group.host.fg : group.host.dim
          font.family: group.host.fontFamily
          font.pixelSize: Style.font.subtitle
        }

        MouseArea {
          id: pickMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: group.host.pointAt(pick.pickKey)
          onClicked: group.host.selectDevice(group.section, pick.modelData)
        }

        PanelToolTip {
          visible: pickMouse.containsMouse
          text: (group.section === "sink" ? "Play through " : "Record from ") + (pick.modelData.label || "this device")
          fontFamily: group.host.fontFamily
        }
      }
    }
  }
}
