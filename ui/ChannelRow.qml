import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Glyphs.js" as Glyphs

// One channel tile: Game, Chat, Media or Aux. Doubles as a drop target: an
// app dragged onto it is assigned to the channel.
CursorSurface {
  id: row

  required property var host
  required property string key
  required property string title

  readonly property var service: host.service
  readonly property bool present: !!(service && service.channels && service.channels[key])
  readonly property real volume: service ? service.volumeOf(key) : 0
  readonly property bool muted: service ? service.mutedOf(key) : false
  readonly property bool dropHot: host.dragKey !== "" && host.dropTarget === key
  readonly property var apps: {
    if (!service) return []
    service.appsVersion
    service.pendingRoutes
    return service.appsIn(key)
  }
  readonly property bool eqActive: host.eqActive(key)

  hasCursor: host.cursorActive && host.cursorKey === "ch:" + key
  current: dropHot
  bordered: true
  foreground: host.fg
  fill: host.hoverFill
  currentFill: host.selectedFill
  implicitHeight: column.implicitHeight + Style.spacing.xl
  height: implicitHeight
  onHasCursorChanged: if (hasCursor) host.ensureVisible(row)

  HoverHandler {
    onHoveredChanged: if (hovered && host.dragKey === "") host.setCursor("ch:" + row.key)
  }

  Column {
    id: column
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(6)
    anchors.rightMargin: Style.space(6)
    spacing: Style.space(2)

    Item {
      width: parent.width
      height: Math.max(Style.space(24), eqButton.height)

      Text {
        id: glyph
        width: Style.space(22)
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: row.muted ? Glyphs.volumeOff : Glyphs.channel(row.key)
        color: row.host.fg
        opacity: row.muted || !row.present ? 0.5 : 1
        font.family: row.host.fontFamily
        font.pixelSize: Style.font.title

        MouseArea {
          anchors.fill: parent
          anchors.margins: -Style.space(3)
          cursorShape: Qt.PointingHandCursor
          onClicked: row.service.setMute(row.key, !row.muted)
        }
      }

      Text {
        anchors.left: glyph.right
        anchors.leftMargin: Style.space(6)
        anchors.right: icons.left
        anchors.rightMargin: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: row.title
        color: row.host.fg
        opacity: row.present ? 1 : 0.5
        font.family: row.host.fontFamily
        font.pixelSize: Style.font.body
        font.bold: row.dropHot
        elide: Text.ElideRight
      }

      // Who is playing into this channel, at most three faces. Anchored from
      // the right so the name elides first in a narrow tile.
      Row {
        id: icons
        anchors.right: pct.left
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        spacing: -Style.space(3)

        Repeater {
          model: row.apps.slice(0, 3)

          Item {
            required property var modelData
            width: Style.space(16)
            height: width

            Image {
              anchors.fill: parent
              visible: status === Image.Ready
              source: parent.modelData.icon || ""
              sourceSize.width: width * 2
              sourceSize.height: height * 2
              smooth: true
              mipmap: true
              asynchronous: true
            }

            Text {
              anchors.centerIn: parent
              visible: !parent.modelData.icon
              text: String(parent.modelData.name || "?").charAt(0).toUpperCase()
              color: row.host.dim
              font.family: row.host.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }
        }
      }

      Text {
        id: pct
        anchors.right: eqButton.left
        anchors.rightMargin: Style.space(2)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: row.muted ? "muted" : Math.round((slider.dragging ? slider.liveValue : row.volume) * 100) + "%"
        color: row.host.dim
        font.family: row.host.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      PanelActionButton {
        id: eqButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        iconText: Glyphs.sliders
        tooltipText: row.title + " equalizer (e)"
        foreground: row.eqActive ? Commons.Color.accent : row.host.fg
        fontFamily: row.host.fontFamily
        opacity: row.eqActive ? 1 : 0.6
        onClicked: row.host.openEq(row.key)
      }
    }

    PanelSlider {
      id: slider
      bar: row.host.bar
      width: parent.width
      minimum: 0
      maximum: 1
      step: 0.01
      value: row.muted ? 0 : row.volume
      opacity: row.muted || !row.present ? 0.5 : 1
      enabled: row.present
      onMoved: function(v) {
        if (row.muted) row.service.setMute(row.key, false)
        row.service.setVolume(row.key, v)
      }
      onRightClicked: row.service.setMute(row.key, !row.muted)

      WheelHandler {
        acceptedDevices: PointerDevice.Mouse
        onWheel: function(event) { row.host.wheelVolume(row.key, event.angleDelta.y) }
      }
    }
  }
}
