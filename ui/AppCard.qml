import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Glyphs.js" as Glyphs

// One app playing sound, as a card inside the channel it plays into. The top
// line is what you pick up: drag it onto another tile, or click it and choose
// a channel from a row of icons. Below it, the app's own mute and fader.
CursorSurface {
  id: card

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
  readonly property bool picking: host.menuKey === key
  readonly property bool keyed: host.cursorActive && host.cursorKey === "app:" + key
  readonly property bool lifted: host.dragKey === key
  readonly property bool muted: !!service && service.mutedOf(key)

  width: parent ? parent.width : implicitWidth
  implicitHeight: body.implicitHeight + Style.space(4) * 2
  height: implicitHeight
  onKeyedChanged: if (keyed) host.ensureVisible(card)

  hasCursor: keyed
  current: picking
  foreground: host.fg
  color: hasCursor ? fill : current ? currentFill : Style.normalFillFor(foreground, accent)
  opacity: lifted ? 0.35 : 1

  HoverHandler {
    onHoveredChanged: if (hovered && card.host.dragKey === "") card.host.pointAt("app:" + card.key)
  }

  WheelHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: function(event) { card.host.wheelVolume(card.key, event.angleDelta.y) }
  }

  Column {
    id: body
    x: Style.space(4)
    y: Style.space(4)
    width: parent.width - x * 2
    spacing: Style.space(2)

    Item {
      id: pickup
      width: parent.width
      height: Math.max(card.host.iconCol, name.implicitHeight)

      // Lights under the pointer, so it reads as the part to grab.
      Rectangle {
        anchors.fill: parent
        anchors.margins: -Style.space(2)
        radius: Style.cornerRadius
        visible: handle.containsMouse
        color: Style.hoverFillFor(card.host.fg, Commons.Color.accent)
      }

      Grip {
        id: grip
        anchors.verticalCenter: parent.verticalCenter
        x: Style.space(1)
        color: handle.containsMouse || card.keyed ? card.host.fg : card.host.dim
      }

      Item {
        id: icon
        x: grip.x + grip.width + Style.space(3)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(16)
        height: width

        Image {
          anchors.fill: parent
          visible: status === Image.Ready
          source: card.app.icon || ""
          sourceSize.width: width * 2
          sourceSize.height: height * 2
          smooth: true
          mipmap: true
          asynchronous: true
          opacity: card.muted ? 0.5 : 1
        }

        Text {
          anchors.centerIn: parent
          visible: !card.app.icon
          textFormat: Text.PlainText
          text: Glyphs.app
          color: card.muted ? card.host.dim : card.host.fg
          font.family: card.host.fontFamily
          font.pixelSize: Style.font.title
        }
      }

      Text {
        id: name
        anchors.left: icon.right
        anchors.leftMargin: Style.space(4)
        anchors.right: chevron.left
        anchors.rightMargin: Style.space(2)
        anchors.verticalCenter: parent.verticalCenter
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: card.app.name || "Unknown"
        color: card.muted ? card.host.dim : card.host.fg
        font.family: card.host.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        id: chevron
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: card.picking ? Glyphs.chevronUp : Glyphs.chevronDown
        color: handle.containsMouse || card.picking ? card.host.fg : card.host.dim
        font.family: card.host.fontFamily
        font.pixelSize: Style.font.body
      }

      DragHandle {
        id: handle
        anchors.fill: parent
        host: card.host
        appKey: card.key
        onTapped: card.host.toggleMenu(card.key)
      }

      PanelToolTip {
        visible: handle.containsMouse && !handle.grabbing && card.host.dragKey === "" && !card.picking
        text: card.host.routeOptions.length > 1 ? "Drag to a channel, or click to pick one" : "Channels are off"
        fontFamily: card.host.fontFamily
      }
    }

    // Where it can go, without dragging: one icon per channel, the current
    // one outlined.
    Flow {
      visible: card.picking
      width: parent.width
      spacing: Style.space(2)

      Repeater {
        model: card.picking ? card.host.routeOptions : []

        PanelActionButton {
          required property var modelData
          width: card.host.iconCol
          height: width
          iconText: Glyphs.channel(modelData.value)
          tooltipText: card.channel === modelData.value
            ? "Playing in " + modelData.label
            : modelData.value === "" ? "Skip the channels" : "Move to " + modelData.label
          bordered: card.channel === modelData.value
          foreground: card.host.fg
          fontFamily: card.host.fontFamily
          onClicked: card.host.assign(card.key, modelData.value)
        }
      }
    }

    TileFader {
      host: card.host
      key: card.key
      name: card.app.name || "this app"
    }
  }
}
