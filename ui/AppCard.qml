import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model
import "Motion.js" as Motion

// One app playing sound, as a small room inside the channel it plays into,
// in that channel's tone. The top line is what you pick up: drag it onto
// another room, or click it to open the channels under it and pick one.
// Below it, the app's own mute and meter, its volume beside it in the pixel
// type, small so the channels' figures stay the big ones. The app keeps its
// own icon, in its own colours.
Rectangle {
  id: card

  required property var host
  // { key, name, icon, binary } from the service's appsIn().
  required property var app
  property color tone: host.fg
  // When the room it sits in comes in, so its meter fills after the room's.
  property int delay: 0

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
  readonly property bool muted: fader.muted
  readonly property real pad: host.snap(Style.space(6))
  // Sound coming out of it now; a paused player keeps its stream, idle.
  readonly property bool playing: {
    if (!service) return false
    service.appsVersion
    var info = service.appInfo[key]
    return !!(info && info.playing)
  }
  // Goes up on a click, to play the fallback icon; and each time the
  // channels open under it, to play theirs.
  property int story: 0
  property int pickPlays: 0
  onPickingChanged: if (picking) pickPlays++

  width: parent ? parent.width : implicitWidth
  implicitHeight: body.implicitHeight + pad * 2
  height: implicitHeight
  radius: Style.cornerRadius
  color: Qt.rgba(tone.r, tone.g, tone.b, picking || keyed || cardHover.hovered ? 0.13 : 0.075)
  border.width: keyed ? Math.max(1, Style.space(1)) : 0
  border.color: Qt.rgba(tone.r, tone.g, tone.b, 0.6)
  opacity: lifted ? 0.35 : 1
  onKeyedChanged: if (keyed) host.ensureVisible(card)

  Behavior on color { ColorAnimation { duration: Style.duration(140) } }

  HoverHandler {
    id: cardHover
    onHoveredChanged: if (hovered && card.host.dragKey === "") card.host.pointAt("app:" + card.key)
  }

  WheelHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: function(event) { card.host.wheelVolume(card.key, event.angleDelta.y) }
  }

  Column {
    id: body
    x: card.pad
    y: card.pad
    width: parent.width - x * 2
    spacing: Style.space(6)

    Item {
      id: pickup
      width: parent.width
      height: Math.max(icon.height, name.implicitHeight)

      Grip {
        id: grip
        anchors.verticalCenter: parent.verticalCenter
        x: Style.space(1)
        color: handle.containsMouse || card.keyed ? card.host.fg : card.host.dim
      }

      Item {
        id: icon
        x: card.host.snap(grip.x + grip.width + Style.space(5))
        y: Math.round((parent.height - height) / 2)
        width: card.host.snap(Style.space(16))
        height: width

        Image {
          id: appImage
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

        // No icon to be had: a plain app window.
        PixelIcon {
          anchors.centerIn: parent
          visible: appImage.status !== Image.Ready
          name: "app-windows"
          size: Style.font.title
          color: card.muted ? card.host.dim : card.tone
          play: card.story
        }
      }

      Text {
        id: name
        anchors.left: icon.right
        anchors.leftMargin: card.host.snap(Style.space(6))
        anchors.right: bars.left
        anchors.rightMargin: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        textFormat: Text.PlainText
        // Three lines at most; a longer name ends in an ellipsis and shows
        // in full in the card's tooltip.
        maximumLineCount: 3
        elide: Text.ElideRight
        text: Model.wrapName(card.app.name || "Unknown", Model.monoColumns(width, card.host.textSize))
        color: card.muted ? card.host.dim : card.host.fg
        font.family: card.host.fontFamily
        font.pixelSize: card.host.textSize
        renderType: Text.NativeRendering
      }

      // Its equaliser: the bars play while sound comes out, on the panel's
      // one clock, and stand still, dimmed, while it is paused.
      PixelIcon {
        id: bars
        anchors.right: chevron.left
        anchors.rightMargin: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        custom: Motion.eqArt(card.host.motionTick, card.playing && !card.muted && !Style.reduceMotion)
        size: Style.font.caption
        color: card.playing && !card.muted ? card.tone : card.host.dim
      }

      PixelIcon {
        id: chevron
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        name: "chevron-down"
        size: Style.font.caption
        color: handle.containsMouse || card.picking ? card.host.fg : card.host.dim
        rotation: card.picking ? 180 : 0
      }

      DragHandle {
        id: handle
        anchors.fill: parent
        host: card.host
        appKey: card.key
        onTapped: {
          card.story++
          card.host.toggleMenu(card.key)
        }
      }

      PanelToolTip {
        visible: handle.containsMouse && !handle.grabbing && card.host.dragKey === "" && !card.picking
        text: (name.truncated ? (card.app.name || "") + "\n" : "")
          + (card.host.routeOptions.length > 1 ? "Drag to a channel, or click to pick one" : "Channels are off")
        fontFamily: card.host.fontFamily
      }
    }

    Item {
      width: parent.width
      height: fader.implicitHeight

      Fader {
        id: fader
        anchors.left: parent.left
        anchors.right: figure.left
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        host: card.host
        key: card.key
        name: card.app.name || "this app"
        tone: card.tone
        small: true
        column: Style.font.title + Style.space(2)
        delay: card.delay
        columnGap: Style.space(5)
      }

      // As wide as "100%", so every card's meter ends in the same place.
      Item {
        id: figure
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Model.pixelText("100%").width * percent.cell
        height: percent.implicitHeight

        PixelText {
          id: percent
          anchors.right: parent.right
          text: Math.round(fader.shown) + "%"
          size: Style.font.caption * 0.8
          color: card.muted ? card.host.dim : card.host.fg
        }
      }
    }

    // Where it can go, without dragging: one button per channel in that
    // channel's tone, the one it plays in outlined.
    Drawer {
      open: card.picking
      spacing: 0

      Row {
        spacing: Style.space(3)

        Repeater {
          model: card.host.routeOptions

          Rectangle {
            id: route
            required property var modelData
            required property int index
            readonly property bool here: card.channel === modelData.value
            readonly property color routeTone: card.host.toneFor(modelData.value)

            width: Style.space(24)
            height: width
            radius: Style.cornerRadius
            color: Qt.rgba(routeTone.r, routeTone.g, routeTone.b, routeMouse.containsMouse ? 0.2 : here ? 0.14 : 0.07)
            border.width: here ? Math.max(1, Style.space(1)) : 0
            border.color: Qt.rgba(routeTone.r, routeTone.g, routeTone.b, 0.7)

            PixelIcon {
              id: routeIcon
              anchors.centerIn: parent
              name: Model.channelPixel(route.modelData.value)
              size: Style.font.title
              color: route.routeTone
              play: card.pickPlays + routeMouse.hovers
              playDelay: routeMouse.containsMouse ? 0 : route.index * 70
            }

            MouseArea {
              id: routeMouse
              // Pointing at a channel plays its icon.
              property int hovers: 0
              anchors.fill: parent
              hoverEnabled: true
              onEntered: hovers++
              cursorShape: Qt.PointingHandCursor
              onClicked: card.host.assign(card.key, route.modelData.value)
            }

            PanelToolTip {
              visible: routeMouse.containsMouse
              text: route.here
                ? "Playing in " + route.modelData.label
                : route.modelData.value === "" ? "Skip the channels" : "Move to " + route.modelData.label
              fontFamily: card.host.fontFamily
            }
          }
        }
      }
    }
  }
}
