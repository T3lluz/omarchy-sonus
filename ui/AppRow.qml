import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Glyphs.js" as Glyphs

// One app playing sound, inside the lane of the channel it plays into: a
// chip with a grip that picks the app up, then its own fader and level on
// the panel's grid. Drag the chip to another lane to move the app there, or
// click it to pick a channel from a row of buttons.
Item {
  id: row

  required property var host
  // { key, name, icon } from the service's appsIn().
  required property var app

  readonly property var service: host.service
  readonly property string key: app.key
  readonly property string channel: {
    if (!service) return ""
    service.appsVersion
    var info = service.appInfo[key]
    return service.effectiveChannel(key, info ? info.channel : "")
  }
  readonly property bool muted: !!service && service.mutedOf(key)
  readonly property real level: fader.dragging ? fader.liveValue : (service ? service.volumeOf(key) : 0)
  readonly property bool picking: host.menuKey === key
  readonly property bool hasCursor: host.cursorActive && host.cursorKey === "app:" + key
  readonly property bool lifted: host.dragKey === key

  width: parent ? parent.width : 0
  implicitHeight: picker.visible ? picker.y + picker.height : line.height
  height: implicitHeight
  onHasCursorChanged: if (hasCursor) host.ensureVisible(row)

  HoverHandler {
    onHoveredChanged: if (hovered && row.host.dragKey === "") row.host.pointAt("app:" + row.key)
  }

  WheelHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: function(event) { row.host.wheelVolume(row.key, event.angleDelta.y) }
  }

  Item {
    id: line
    width: parent.width
    height: Math.max(chip.height, fader.height)

    // The chip: grip, icon and name, lit under the pointer so it reads as
    // something to pick up.
    CursorSurface {
      id: chip
      x: row.host.chipX
      width: row.host.chipWidth
      height: Math.max(row.host.chipH, chipName.implicitHeight + Style.space(8))
      anchors.verticalCenter: parent.verticalCenter
      bordered: true
      hasCursor: handle.containsMouse || row.hasCursor
      current: row.picking
      foreground: row.host.fg
      opacity: row.lifted ? 0.35 : 1

      // Three rows of two dots: the usual sign for "drag me".
      Grid {
        id: grip
        x: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        columns: 2
        spacing: Style.space(2)

        Repeater {
          model: 6
          Rectangle {
            width: Math.max(2, Style.space(2))
            height: width
            radius: width / 2
            color: handle.containsMouse || row.hasCursor ? row.host.fg : row.host.dim
          }
        }
      }

      Item {
        id: icon
        x: grip.x + grip.width + Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(16)
        height: width

        Image {
          anchors.fill: parent
          visible: status === Image.Ready
          source: row.app.icon || ""
          sourceSize.width: width * 2
          sourceSize.height: height * 2
          smooth: true
          mipmap: true
          asynchronous: true
          opacity: row.muted ? 0.5 : 1
        }

        Text {
          anchors.centerIn: parent
          visible: !row.app.icon
          text: Glyphs.app
          color: row.host.fg
          font.family: row.host.fontFamily
          font.pixelSize: parent.height
        }
      }

      Text {
        id: chipName
        anchors.left: icon.right
        anchors.leftMargin: Style.space(6)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: row.app.name || "Unknown"
        color: row.muted ? row.host.dim : row.host.fg
        font.family: row.host.fontFamily
        font.pixelSize: Style.font.body
      }

      DragHandle {
        id: handle
        anchors.fill: parent
        host: row.host
        appKey: row.key
        onTapped: row.host.toggleMenu(row.key)
      }

      PanelToolTip {
        visible: handle.containsMouse && !handle.grabbing && row.host.dragKey === "" && !row.picking
        text: "Drag to another channel, or click to pick one"
        fontFamily: row.host.fontFamily
      }
    }

    PanelSlider {
      id: fader
      bar: row.host.bar
      x: row.host.faderX
      width: row.host.faderWidth(line.width)
      anchors.verticalCenter: parent.verticalCenter
      minimum: 0
      maximum: 1
      step: 0.05
      value: row.service ? row.service.volumeOf(row.key) : 0
      opacity: row.muted ? 0.4 : 1
      onMoved: function(v) {
        if (row.muted) row.service.setMute(row.key, false)
        row.service.setVolume(row.key, v)
      }
      onRightClicked: row.service.setMute(row.key, !row.muted)
    }

    Reading {
      anchors.right: parent.right
      anchors.rightMargin: row.host.rowPad
      anchors.verticalCenter: parent.verticalCenter
      value: row.level
      muted: row.muted
      size: row.host.readingSize
      color: row.host.fg
      dim: row.host.dim
      fontFamily: row.host.fontFamily

      MouseArea {
        id: muteMouse
        anchors.fill: parent
        anchors.margins: -Style.space(3)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.service.setMute(row.key, !row.muted)
      }

      PanelToolTip {
        visible: muteMouse.containsMouse
        text: (row.muted ? "Unmute " : "Mute ") + (row.app.name || "this app") + " (m)"
        fontFamily: row.host.fontFamily
      }
    }
  }

  // The click-instead-of-drag way: every channel as a button.
  ButtonGroup {
    id: picker
    visible: row.picking
    x: row.host.chipX
    y: line.height + Style.space(4)
    width: parent.width - x - row.host.rowPad
    options: row.host.routeOptions
    value: row.channel
    foreground: row.host.fg
    fontFamily: row.host.fontFamily
    fontSize: Style.font.caption
    onChanged: function(value) { row.host.assign(row.key, value) }
  }
}
