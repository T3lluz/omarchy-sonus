import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Glyphs.js" as Glyphs

// One channel: Master or a category. The category rows double as drop
// targets: an app dragged onto one is assigned to it, and Master takes an
// app back to the plain output.
CursorSurface {
  id: row

  required property var host
  required property string key
  required property string title

  readonly property var service: host.service
  readonly property bool isMaster: key === "master"
  readonly property bool present: !!(service && service.channels && service.channels[key])
  readonly property real volume: service ? service.volumeOf(key) : 0
  readonly property bool muted: service ? service.mutedOf(key) : false
  readonly property bool dropHot: host.dragKey !== "" && host.dropTarget === key
  readonly property var apps: {
    if (!service || isMaster) return []
    service.appsVersion
    service.pendingRoutes
    return service.appsIn(key)
  }
  readonly property bool eqActive: !isMaster && host.eqActive(key)

  hasCursor: host.cursorActive && host.cursorKey === "ch:" + key
  current: dropHot
  outline: dropHot
  foreground: host.fg
  fill: host.hoverFill
  currentFill: host.selectedFill
  implicitHeight: column.implicitHeight + Style.spacing.lg
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
        id: name
        anchors.left: glyph.right
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: row.title
        color: row.host.fg
        opacity: row.present ? 1 : 0.5
        font.family: row.host.fontFamily
        font.pixelSize: Style.font.body
        font.bold: row.isMaster || row.dropHot
      }

      // Who is playing into this channel.
      Row {
        anchors.left: name.right
        anchors.leftMargin: Style.space(10)
        anchors.right: pct.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)
        clip: true

        Repeater {
          model: row.apps

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

        Text {
          visible: row.dropHot
          anchors.verticalCenter: parent.verticalCenter
          text: row.isMaster ? "release to unassign" : "release to assign"
          color: row.host.dim
          font.family: row.host.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        id: pct
        anchors.right: eqButton.visible ? eqButton.left : parent.right
        anchors.rightMargin: eqButton.visible ? Style.space(4) : 0
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
        visible: !row.isMaster
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
