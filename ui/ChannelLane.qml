import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Audio.js" as Audio
import "Eq.js" as Eq
import "Glyphs.js" as Glyphs

// One channel and the apps playing into it. The channel's row is on the
// panel's grid (icon, name over its EQ, fader, level); its apps sit under
// it as chips, each with its own fader. Drag a chip to another lane to move
// the app; while one is dragged every lane outlines itself as a place to
// drop it. With no `key` the lane holds the apps that skip the channels.
Item {
  id: lane

  required property var host
  property string key: ""
  property string title: ""

  readonly property var service: host.service
  readonly property bool isChannel: key !== ""
  // What a drop here means to the panel: a channel, or "master" for none.
  readonly property string dropKey: isChannel ? key : "master"
  readonly property bool present: !isChannel || !!(service && service.channels && service.channels[key])
  readonly property bool muted: isChannel && !!service && service.mutedOf(key)
  readonly property real level: fader.dragging ? fader.liveValue : (service && isChannel ? service.volumeOf(key) : 0)
  readonly property bool dragging: host.dragKey !== ""
  readonly property bool dropHot: dragging && host.dropTarget === dropKey
  readonly property var eq: Eq.normalized(service && service.eqs && isChannel ? service.eqs[key] : null)
  readonly property bool eqShaping: eq.enabled && !Eq.isFlat(eq)
  readonly property bool hasCursor: host.cursorActive && host.cursorKey === "ch:" + key
  readonly property var apps: {
    if (!service) return []
    service.appsVersion
    service.pendingRoutes
    return service.appsIn(key)
  }

  width: parent ? parent.width : 0
  implicitHeight: content.implicitHeight
  height: implicitHeight
  onHasCursorChanged: if (hasCursor) host.ensureVisible(row)

  function toggleMute() { if (service && present && isChannel) service.setMute(key, !muted) }

  // A drop zone only while an app is in the air: outlined, and filled when
  // the app is over it.
  CursorSurface {
    anchors.fill: parent
    bordered: lane.dragging
    current: lane.dropHot
    foreground: lane.host.fg
  }

  Column {
    id: content
    width: parent.width
    bottomPadding: lane.apps.length > 0 || slot.visible ? Style.space(8) : 0

    Item {
      id: row
      width: parent.width
      height: Math.max(lines.implicitHeight, fader.height) + Style.space(12)

      CursorSurface {
        anchors.fill: parent
        hasCursor: lane.hasCursor
        foreground: lane.host.fg
      }

      HoverHandler {
        onHoveredChanged: if (hovered && lane.isChannel && lane.host.dragKey === "") lane.host.pointAt("ch:" + lane.key)
      }

      WheelHandler {
        enabled: lane.isChannel
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function(event) { lane.host.wheelVolume(lane.key, event.angleDelta.y) }
      }

      Art {
        x: lane.host.rowPad
        anchors.verticalCenter: parent.verticalCenter
        width: lane.host.iconW
        height: lane.host.iconH
        name: lane.isChannel ? Audio.channelDrawing(lane.key) : "speaker"
        color: lane.host.fg
        opacity: lane.muted || !lane.present ? 0.4 : 1

        MouseArea {
          id: artMouse
          anchors.fill: parent
          anchors.margins: -Style.space(4)
          enabled: lane.isChannel
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: lane.toggleMute()
        }

        PanelToolTip {
          visible: artMouse.containsMouse && lane.isChannel
          text: (lane.muted ? "Unmute " : "Mute ") + lane.title + " (m)"
          fontFamily: lane.host.fontFamily
        }
      }

      Column {
        id: lines
        x: lane.host.nameX
        width: lane.isChannel ? lane.host.nameW : parent.width - x - lane.host.rowPad
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          width: parent.width
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          text: lane.title
          color: lane.present ? lane.host.fg : lane.host.dim
          font.family: lane.host.fontFamily
          font.pixelSize: Style.font.subtitle
        }

        // The channel's EQ in two words, and the way into it.
        Text {
          visible: lane.isChannel
          textFormat: Text.PlainText
          text: Glyphs.sliders + " " + Audio.eqWord(lane.eq.enabled, Eq.isFlat(lane.eq))
          color: lane.eqShaping || eqMouse.containsMouse ? lane.host.fg : lane.host.dim
          font.family: lane.host.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: lane.eqShaping

          MouseArea {
            id: eqMouse
            anchors.fill: parent
            anchors.margins: -Style.space(3)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: lane.host.openEq(lane.key)
          }

          PanelToolTip {
            visible: eqMouse.containsMouse
            text: "Open the " + lane.title + " equalizer (e)"
            fontFamily: lane.host.fontFamily
          }
        }

        Text {
          visible: !lane.isChannel
          width: parent.width
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          text: Audio.directLine(lane.service ? lane.service.outputLabel : "")
          color: lane.host.dim
          font.family: lane.host.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      PanelSlider {
        id: fader
        visible: lane.isChannel
        bar: lane.host.bar
        x: lane.host.faderX
        width: lane.host.faderWidth(row.width)
        anchors.verticalCenter: parent.verticalCenter
        minimum: 0
        maximum: 1
        step: 0.05
        value: lane.service && lane.isChannel ? lane.service.volumeOf(lane.key) : 0
        opacity: !lane.present || lane.muted ? 0.4 : 1
        enabled: lane.present
        onMoved: function(v) {
          if (lane.muted) lane.service.setMute(lane.key, false)
          lane.service.setVolume(lane.key, v)
        }
        onRightClicked: lane.toggleMute()
      }

      Reading {
        visible: lane.isChannel
        anchors.right: parent.right
        anchors.rightMargin: lane.host.rowPad
        anchors.verticalCenter: parent.verticalCenter
        value: lane.level
        muted: lane.muted
        size: lane.host.readingSize
        color: lane.present ? lane.host.fg : lane.host.dim
        dim: lane.host.dim
        fontFamily: lane.host.fontFamily
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(4)

      Repeater {
        model: lane.apps

        AppRow {
          required property var modelData
          host: lane.host
          app: modelData
        }
      }
    }

    // Where an app can land when the lane has none: dashed, so it reads as
    // an empty slot, and only once there is an app to drag.
    Item {
      id: slot
      visible: lane.isChannel && lane.apps.length === 0 && lane.host.appCount > 0
      x: lane.host.chipX
      width: lane.host.chipWidth
      height: lane.host.chipH

      Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
          strokeColor: Qt.rgba(lane.host.fg.r, lane.host.fg.g, lane.host.fg.b, lane.dropHot ? 0.6 : 0.25)
          strokeWidth: Math.max(1, Style.space(1))
          strokeStyle: ShapePath.DashLine
          dashPattern: [3, 3]
          fillColor: "transparent"
          startX: 0.5; startY: 0.5
          PathLine { x: slot.width - 0.5; y: 0.5 }
          PathLine { x: slot.width - 0.5; y: slot.height - 0.5 }
          PathLine { x: 0.5; y: slot.height - 0.5 }
          PathLine { x: 0.5; y: 0.5 }
        }
      }

      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: lane.dragging ? "Drop here" : "Drag an app here"
        color: lane.dropHot ? lane.host.fg : lane.host.dim
        font.family: lane.host.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
