import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Audio.js" as Audio
import "Eq.js" as Eq
import "Model.js" as Model

// One channel as a room. The top is the channel itself: its icon and name,
// how many apps play in it, its volume in the block face and its fader. A
// click opens its equalizer settings under the fader. The bottom is its
// bucket, holding the apps that play into it. Every bucket starts at the same
// height and is tall enough for one app, so moving an app does not reflow the
// row, and the empty part of a bucket is as good a place to drop as any.
Room {
  id: tile

  required property string key
  required property string title

  readonly property var service: host.service
  // What a drop here means to the panel.
  readonly property string dropKey: key
  readonly property bool accepting: channelPresent
  // The tile an app is lifted from is no place to drop it.
  readonly property bool holdsDrag: dragging && apps.some(function(a) { return a.key === host.dragKey })
  readonly property bool channelPresent: !!(service && service.channels && service.channels[key])
  readonly property bool muted: fader.muted
  readonly property bool dragging: host.dragKey !== ""
  readonly property var eq: Eq.normalized(service && service.eqs ? service.eqs[key] : null)
  readonly property bool eqShaping: eq.enabled && !Eq.isFlat(eq)
  readonly property var apps: {
    if (!service) return []
    service.appsVersion
    service.pendingRoutes
    return service.appsIn(key)
  }

  readonly property real bucketMargin: host.snap(Style.space(3))
  // One card's height, with the bucket's own margin.
  readonly property real bucketMin: Style.space(54)
  readonly property real bucketNeed: Math.max(bucketMin, cards.implicitHeight + bucketMargin * 2)

  tone: host.toneFor(key)
  cells: [fader.meter]
  expanded: host.openChannel === key
  keyed: host.cursorActive && host.cursorKey === "ch:" + key
  dropHot: dragging && host.dropTarget === dropKey
  naturalHeight: top.implicitHeight + spacing + bucketNeed
  onKeyedChanged: if (keyed) host.ensureVisible(tile)
  onClicked: if (channelPresent) host.toggleChannel(key)
  // An app starting to play here plays the channel's icon.
  property int appsSeen: 0
  onAppsChanged: {
    if (apps.length > appsSeen && host.opened) story++
    appsSeen = apps.length
  }

  Column {
    id: top
    width: parent.width
    spacing: Style.space(8)

    // On this part and not the room: a card has its own, and `m` should mute
    // whichever one the tooltip under the pointer names.
    HoverHandler {
      onHoveredChanged: if (hovered && tile.host.dragKey === "") tile.host.pointAt("ch:" + tile.key)
    }

    WheelHandler {
      enabled: tile.channelPresent
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
      onWheel: function(event) { tile.host.wheelVolume(tile.key, event.angleDelta.y) }
    }

    RoomHeader {
      host: tile.host
      icon: Model.channelPixel(tile.key)
      tone: tile.tone
      title: tile.title
      status: Audio.channelState(tile.channelPresent, !!tile.service && tile.service.manageGraph, tile.muted, tile.apps.length)
      value: tile.channelPresent ? fader.shown : null
      mark: Model.markFor(tile.muted, false, tile.eqShaping)
      figureDimmed: tile.muted
      dimmed: !tile.channelPresent
      showChevron: tile.channelPresent
      expanded: tile.expanded
      tick: tile.story
      delay: tile.delay + 120
    }

    Fader {
      id: fader
      host: tile.host
      key: tile.key
      name: "everything in " + tile.title
      present: tile.channelPresent
      tone: tile.tone
      delay: tile.delay + 80
    }

    // The channel's own settings: its equalizer, on or off, and the way into
    // the curve.
    Drawer {
      open: tile.expanded

      SwitchRow {
        width: parent.width
        icon: ""
        label: "Equalizer"
        hint: Audio.eqLine(tile.eq.enabled, Eq.presetName(tile.eq.gains), tile.eq.gains, tile.eq.preamp)
        checked: tile.eq.enabled
        foreground: tile.host.fg
        accent: tile.tone
        fontFamily: tile.host.fontFamily
        onToggled: {
          var next = Eq.normalized(tile.eq)
          next.enabled = !next.enabled
          tile.service.setEq(tile.key, next)
        }
      }

      Button {
        width: parent.width
        text: "Edit the curve"
        tooltipText: "Open the " + tile.title + " equalizer (e)"
        bordered: true
        foreground: tile.host.fg
        fontFamily: tile.host.fontFamily
        fontSize: Style.font.bodySmall
        onClicked: tile.host.openEq(tile.key)
      }
    }
  }

  Item {
    id: bucket
    width: parent.width
    height: Math.max(tile.bucketNeed, tile.height - tile.pad * 2 - top.height - tile.spacing)

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
        strokeColor: Qt.rgba(tile.tone.r, tile.tone.g, tile.tone.b, tile.dropHot ? 0.8 : 0.35)
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
      spacing: Style.space(3)

      Repeater {
        model: tile.apps

        AppCard {
          required property var modelData
          host: tile.host
          app: modelData
          tone: tile.tone
          delay: tile.delay + 160
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
      font.pixelSize: tile.host.textSize
      renderType: Text.NativeRendering
    }
  }
}
