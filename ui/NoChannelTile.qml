import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Audio.js" as Audio
import "Model.js" as Model

// The apps that skip the channels, in a room under them with no tone of its
// own: they have no channel. It shows only when it holds an app, or while an
// app is in the air as the way to send one here.
Room {
  id: tile

  // The width of one channel room, so the cards start under Chat's.
  property real labelWidth: 0

  readonly property var service: host.service
  readonly property string dropKey: "master"
  readonly property bool accepting: true
  readonly property bool holdsDrag: dragging && apps.some(function(a) { return a.key === host.dragKey })
  readonly property bool dragging: host.dragKey !== ""
  readonly property var apps: {
    if (!service) return []
    service.appsVersion
    service.pendingRoutes
    return service.appsIn("")
  }

  tone: host.toneFor("")
  dropHot: dragging && host.dropTarget === dropKey
  clickable: false
  naturalHeight: Math.max(head.implicitHeight, flow.implicitHeight)

  Item {
    width: parent.width
    height: tile.naturalHeight

    RoomHeader {
      id: head
      width: tile.labelWidth - tile.pad * 2
      host: tile.host
      icon: Model.channelPixel("")
      tone: tile.tone
      title: "No channel"
      status: Audio.toOutput(tile.service ? tile.service.outputLabel : "")
      showFigure: false
      showChevron: false
      tick: tile.story
      delay: tile.delay + 120

      HoverHandler { id: headHover }

      PanelToolTip {
        visible: headHover.hovered
        text: "Plays straight to the output, without a channel's fader or EQ"
        fontFamily: tile.host.fontFamily
      }
    }

    // Each card sits right under Chat's, Media's and Aux's.
    Flow {
      id: flow
      readonly property real inset: tile.host.snap(tile.pad + Style.space(3))
      readonly property real cardWidth: tile.labelWidth - inset * 2
      x: tile.host.snap(tile.labelWidth + tile.host.roomGap + Style.space(3))
      width: parent.width - x
      spacing: tile.host.roomGap + inset * 2

      Repeater {
        model: tile.apps

        AppCard {
          required property var modelData
          width: flow.cardWidth
          host: tile.host
          app: modelData
          tone: tile.tone
          delay: tile.delay + 160
        }
      }

      MonoText {
        step: "small"
        fontFamily: tile.host.fontFamily
        visible: tile.apps.length === 0
        width: flow.width
        height: head.implicitHeight
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: "Drop here to skip the channels"
        color: tile.dropHot ? tile.host.fg : tile.host.dim
      }
    }
  }
}
