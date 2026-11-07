import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Audio.js" as Audio
import "Eq.js" as Eq
import "Glyphs.js" as Glyphs

// One channel, whole. The top half is the channel itself: its icon and name,
// where it plays, its EQ, its mute and fader. The bottom half is its bucket,
// holding the apps that play into it. Every bucket starts at the same height
// and is tall enough for one app, so moving an app does not reflow the row,
// and the empty part of a bucket is as good a place to drop as any.
CursorSurface {
  id: tile

  required property var host
  required property string key
  required property string title

  readonly property var service: host.service
  // What a drop here means to the panel.
  readonly property string dropKey: key
  readonly property bool accepting: channelPresent
  // The tile an app is lifted from is no place to drop it.
  readonly property bool holdsDrag: dragging && apps.some(function(a) { return a.key === host.dragKey })
  readonly property bool channelPresent: !!(service && service.channels && service.channels[key])
  readonly property bool muted: !!service && service.mutedOf(key)
  readonly property bool dragging: host.dragKey !== ""
  readonly property bool dropHot: dragging && host.dropTarget === dropKey
  readonly property var eq: Eq.normalized(service && service.eqs ? service.eqs[key] : null)
  readonly property bool eqShaping: eq.enabled && !Eq.isFlat(eq)
  readonly property bool keyed: host.cursorActive && host.cursorKey === "ch:" + key
  readonly property var apps: {
    if (!service) return []
    service.appsVersion
    service.pendingRoutes
    return service.appsIn(key)
  }

  // One card's height, with the bucket's own margin.
  readonly property real bucketMargin: Style.space(3)
  readonly property real bucketMin: Style.space(60)
  readonly property real gap: Style.space(4)

  implicitHeight: host.tilePad * 2 + top.implicitHeight + gap
    + Math.max(bucketMin, cards.implicitHeight + bucketMargin * 2)
  onKeyedChanged: if (keyed) host.ensureVisible(tile)

  hasCursor: keyed
  current: dropHot
  bordered: dragging && accepting && !holdsDrag
  foreground: host.fg
  color: hasCursor ? fill : current ? currentFill : Style.normalFillFor(foreground, accent)

  Column {
    id: top
    x: tile.host.tilePad
    y: tile.host.tilePad
    width: parent.width - x * 2
    spacing: Style.space(2)

    // On this half and not the tile: a card has its own, and `m` should mute
    // whichever one the tooltip under the pointer names.
    HoverHandler {
      onHoveredChanged: if (hovered && tile.host.dragKey === "") tile.host.pointAt("ch:" + tile.key)
    }

    WheelHandler {
      enabled: tile.channelPresent
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
      onWheel: function(event) { tile.host.wheelVolume(tile.key, event.angleDelta.y) }
    }

    TileHead {
      host: tile.host
      icon: Glyphs.channel(tile.key)
      iconTip: tile.title + " channel: one fader and EQ for the apps in it"
      title: tile.title
      line: Audio.channelLine(tile.channelPresent, !!tile.service && tile.service.manageGraph, tile.muted,
        tile.service ? tile.service.outputLabel : "")
      dimmed: tile.muted || !tile.channelPresent

      // The way into the channel's equalizer, always a button: filled and
      // bright while it shapes the sound, as Omarchy marks a chosen option.
      CursorSurface {
        visible: tile.channelPresent
        width: Style.space(24)
        height: tile.host.iconCol
        hasCursor: eqMouse.containsMouse
        current: tile.eqShaping
        bordered: true
        foreground: tile.host.fg

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: "EQ"
          color: tile.eqShaping || eqMouse.containsMouse ? tile.host.fg : tile.host.dim
          font.family: tile.host.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        MouseArea {
          id: eqMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: tile.host.openEq(tile.key)
        }

        PanelToolTip {
          visible: eqMouse.containsMouse
          text: Audio.eqWord(tile.eq.enabled, Eq.isFlat(tile.eq)) + ". Open the " + tile.title + " equalizer (e)"
          fontFamily: tile.host.fontFamily
        }
      }
    }

    TileFader {
      host: tile.host
      key: tile.key
      name: "everything in " + tile.title
      present: tile.channelPresent
    }
  }

  Item {
    id: bucket
    x: tile.host.tilePad
    y: top.y + top.height + tile.gap
    width: parent.width - x * 2
    height: Math.max(tile.bucketMin, parent.height - y - tile.host.tilePad)

    // The rest of the bucket answers for the channel, or the keys would still
    // act on the card the pointer just left.
    HoverHandler {
      onPointChanged: {
        if (!hovered || tile.host.dragKey !== "") return
        if (!cards.childAt(point.position.x - cards.x, point.position.y - cards.y)) tile.host.pointAt("ch:" + tile.key)
      }
    }

    // Dashed only where it means something: an empty bucket, or any place an
    // app could land while one is in the air.
    Shape {
      anchors.fill: parent
      visible: tile.channelPresent && (tile.apps.length === 0 || (tile.dragging && !tile.holdsDrag))
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        strokeColor: Qt.rgba(tile.host.fg.r, tile.host.fg.g, tile.host.fg.b, tile.dropHot ? 0.6 : 0.25)
        strokeWidth: Math.max(1, Style.space(1))
        strokeStyle: ShapePath.DashLine
        dashPattern: [3, 3]
        fillColor: "transparent"
        startX: 0.5; startY: 0.5
        PathLine { x: bucket.width - 0.5; y: 0.5 }
        PathLine { x: bucket.width - 0.5; y: bucket.height - 0.5 }
        PathLine { x: 0.5; y: bucket.height - 0.5 }
        PathLine { x: 0.5; y: 0.5 }
      }
    }

    Column {
      id: cards
      x: tile.bucketMargin
      y: tile.bucketMargin
      width: parent.width - x * 2
      spacing: Style.space(4)

      Repeater {
        model: tile.apps

        AppCard {
          required property var modelData
          host: tile.host
          app: modelData
        }
      }
    }

    Text {
      anchors.centerIn: parent
      width: parent.width - Style.space(8)
      visible: tile.apps.length === 0
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      textFormat: Text.PlainText
      text: Audio.bucketLine(tile.channelPresent, tile.dragging, tile.host.appCount)
      color: tile.host.dim
      font.family: tile.host.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
