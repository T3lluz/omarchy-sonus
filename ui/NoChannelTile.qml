import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Audio.js" as Audio
import "Glyphs.js" as Glyphs

// The apps that skip the channels, in a strip under them. It shows only when
// it holds an app, or while an app is in the air as the way to send one here.
CursorSurface {
  id: tile

  required property var host
  // The width of one channel tile, so the strip's cards start past its name.
  property real labelWidth: 0

  readonly property var service: host.service
  readonly property string dropKey: "master"
  readonly property bool accepting: true
  readonly property bool holdsDrag: dragging && apps.some(function(a) { return a.key === host.dragKey })
  readonly property bool dragging: host.dragKey !== ""
  readonly property bool dropHot: dragging && host.dropTarget === dropKey
  readonly property var apps: {
    if (!service) return []
    service.appsVersion
    service.pendingRoutes
    return service.appsIn("")
  }

  implicitHeight: Math.max(head.implicitHeight, flow.implicitHeight) + host.tilePad * 2

  current: dropHot
  bordered: dragging && !holdsDrag
  foreground: host.fg
  color: current ? currentFill : Style.normalFillFor(foreground, accent)

  TileHead {
    id: head
    x: tile.host.tilePad
    y: tile.host.tilePad
    width: tile.labelWidth - tile.host.tilePad * 2
    host: tile.host
    icon: Glyphs.noChannel
    iconTip: "Plays straight to the output, without a channel's fader or EQ"
    title: "No channel"
    line: Audio.toOutput(tile.service ? tile.service.outputLabel : "")
  }

  // Each card sits right under Chat's, Media's and Aux's.
  Flow {
    id: flow
    readonly property real inset: tile.host.tilePad + Style.space(3)
    readonly property real cardWidth: tile.labelWidth - inset * 2
    x: tile.labelWidth + tile.host.tileGap + inset
    y: tile.host.tilePad
    width: parent.width - x
    spacing: tile.host.tileGap + inset * 2

    Repeater {
      model: tile.apps

      AppCard {
        required property var modelData
        width: flow.cardWidth
        host: tile.host
        app: modelData
      }
    }

    Text {
      visible: tile.apps.length === 0
      width: flow.width
      height: head.implicitHeight
      verticalAlignment: Text.AlignVCenter
      wrapMode: Text.Wrap
      textFormat: Text.PlainText
      text: "Drop here to skip the channels"
      color: tile.dropHot ? tile.host.fg : tile.host.dim
      font.family: tile.host.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
