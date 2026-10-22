import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Glyphs.js" as Glyphs

// One app playing sound. Its category button opens a picker row; the name
// line is also a grab handle: drag it onto a channel to assign the app.
CursorSurface {
  id: row

  required property var host
  required property var model

  readonly property var service: host.service
  readonly property string key: model.key
  readonly property string channel: service ? service.effectiveChannel(model.key, model.channel) : ""
  readonly property real volume: service ? service.volumeOf(key) : 0
  readonly property bool muted: service ? service.mutedOf(key) : false
  readonly property bool picking: host.menuKey === key

  hasCursor: host.cursorActive && host.cursorKey === "app:" + key
  current: picking
  foreground: host.fg
  fill: host.hoverFill
  currentFill: host.selectedFill
  opacity: host.dragKey === key ? 0.45 : 1
  implicitHeight: column.implicitHeight + Style.spacing.lg
  onHasCursorChanged: if (hasCursor) host.ensureVisible(row)

  HoverHandler {
    onHoveredChanged: if (hovered && host.dragKey === "") host.setCursor("app:" + row.key)
  }

  Column {
    id: column
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(6)
    anchors.rightMargin: Style.space(6)
    spacing: Style.space(4)

    Item {
      width: parent.width
      height: Math.max(Style.space(24), chooser.implicitHeight)

      Item {
        id: icon
        width: Style.space(22)
        height: Style.space(18)
        anchors.verticalCenter: parent.verticalCenter

        Image {
          anchors.centerIn: parent
          width: Style.space(18)
          height: width
          visible: status === Image.Ready
          source: row.model.icon || ""
          sourceSize.width: width * 2
          sourceSize.height: height * 2
          smooth: true
          mipmap: true
          asynchronous: true
          opacity: row.muted ? 0.5 : 1
        }

        Text {
          anchors.centerIn: parent
          visible: !row.model.icon
          text: Glyphs.app
          color: row.host.fg
          font.family: row.host.fontFamily
          font.pixelSize: Style.font.title
        }
      }

      Text {
        id: name
        anchors.left: icon.right
        anchors.leftMargin: Style.space(8)
        anchors.right: chooser.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: row.model.name
        color: row.host.fg
        opacity: row.muted ? 0.5 : 1
        font.family: row.host.fontFamily
        font.pixelSize: Style.font.body
      }

      // Grab handle over the icon and name.
      MouseArea {
        id: grabArea
        anchors.left: parent.left
        anchors.right: chooser.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        cursorShape: grabbing ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property bool grabbing: false
        property real pressX: 0
        property real pressY: 0
        preventStealing: true
        onPressed: function(event) {
          pressX = event.x
          pressY = event.y
          grabbing = false
        }
        onPositionChanged: function(event) {
          if (!pressed) return
          if (!grabbing && Math.abs(event.x - pressX) + Math.abs(event.y - pressY) > 8) grabbing = true
          if (grabbing) row.host.dragMove(row.key, grabArea, event.x, event.y)
        }
        onReleased: function(event) {
          if (grabbing) row.host.dragRelease(row.key, grabArea, event.x, event.y)
          else row.host.toggleMenu(row.key)
          grabbing = false
        }
        onCanceled: {
          grabbing = false
          row.host.endDrag()
        }
      }

      Button {
        id: chooser
        anchors.right: pct.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: row.channel ? row.host.channelTitle(row.channel) : "Output"
        iconText: row.channel ? Glyphs.channel(row.channel) : Glyphs.speaker
        tooltipText: "Send to a channel (1-4, 0 for output)"
        selected: row.picking
        bordered: true
        foreground: row.host.fg
        fontFamily: row.host.fontFamily
        fontSize: Style.font.caption
        iconSize: Style.font.bodySmall
        verticalPadding: Style.space(2)
        horizontalPadding: Style.space(7)
        onClicked: row.host.toggleMenu(row.key)
      }

      Text {
        id: pct
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(34)
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText
        text: row.muted ? "muted" : Math.round((slider.dragging ? slider.liveValue : row.volume) * 100) + "%"
        color: row.host.dim
        font.family: row.host.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }

    Row {
      width: parent.width
      spacing: Style.space(8)

      Text {
        id: muteGlyph
        width: Style.space(22)
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignHCenter
        text: row.muted ? Glyphs.volumeOff : Glyphs.volumeHigh
        color: row.host.fg
        opacity: row.muted ? 0.5 : 0.8
        font.family: row.host.fontFamily
        font.pixelSize: Style.font.body

        MouseArea {
          anchors.fill: parent
          anchors.margins: -Style.space(3)
          cursorShape: Qt.PointingHandCursor
          onClicked: row.service.setMute(row.key, !row.muted)
        }
      }

      PanelSlider {
        id: slider
        bar: row.host.bar
        width: parent.width - muteGlyph.width - Style.space(8)
        minimum: 0
        maximum: 1
        step: 0.01
        value: row.muted ? 0 : row.volume
        opacity: row.muted ? 0.5 : 1
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

    ButtonGroup {
      visible: row.picking
      options: row.host.routeOptions
      value: row.channel
      foreground: row.host.fg
      fontFamily: row.host.fontFamily
      fontSize: Style.font.caption
      onChanged: function(value) { row.host.assign(row.key, value) }
    }
  }
}
