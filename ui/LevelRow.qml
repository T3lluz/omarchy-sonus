import QtQuick
import qs.Commons
import qs.Ui

// The system level for the output or the input: a mute glyph, the slider and,
// for the input, a live meter under it.
CursorSurface {
  id: row

  required property var host
  required property string key
  required property string cursor
  property string glyph: ""
  property bool metered: false
  property real peak: 0

  readonly property var service: host.service
  readonly property bool present: !!(service && service.channels && service.channels[key])
  readonly property bool muted: !!service && service.mutedOf(key)
  readonly property real shownVolume: slider.dragging ? slider.liveValue : (service ? service.volumeOf(key) : 0)

  width: parent ? parent.width : implicitWidth
  height: controls.implicitHeight + Style.spacing.controlGap
  hasCursor: host.cursorActive && host.cursorKey === cursor
  onHasCursorChanged: if (hasCursor) host.ensureVisible(row)
  foreground: host.fg
  outline: true

  function toggleMute() { if (service) service.setMute(key, !muted) }

  Column {
    id: controls
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(6)
    anchors.rightMargin: Style.space(6)
    spacing: Style.space(5)

    Row {
      width: parent.width
      spacing: Style.space(8)

      Text {
        id: glyphText
        width: Style.space(22)
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: row.glyph
        color: row.host.fg
        opacity: row.muted ? 0.5 : 1
        font.family: row.host.fontFamily
        font.pixelSize: Style.font.title

        MouseArea {
          anchors.fill: parent
          anchors.margins: -Style.space(3)
          cursorShape: Qt.PointingHandCursor
          onClicked: row.toggleMute()
        }
      }

      PanelSlider {
        id: slider
        bar: row.host.bar
        width: parent.width - glyphText.width - parent.spacing
        anchors.verticalCenter: parent.verticalCenter
        minimum: 0
        maximum: 1
        step: 0.05
        value: row.present && !row.muted ? row.service.volumeOf(row.key) : 0
        opacity: !row.present || row.muted ? 0.5 : 1
        enabled: row.present
        onMoved: function(v) {
          if (row.muted) row.service.setMute(row.key, false)
          row.service.setVolume(row.key, v)
        }
        onRightClicked: row.toggleMute()

        WheelHandler {
          acceptedDevices: PointerDevice.Mouse
          onWheel: function(event) { row.host.wheelVolume(row.key, event.angleDelta.y) }
        }
      }
    }

    // Lines up under the slider, not the glyph.
    Rectangle {
      visible: row.metered
      x: glyphText.width + Style.space(8)
      width: parent.width - x
      height: Math.max(Style.space(4), Style.spacing.xs)
      radius: Style.cornerRadius > 0 ? height / 2 : 0
      color: Qt.rgba(row.host.fg.r, row.host.fg.g, row.host.fg.b, 0.18)
      opacity: row.muted ? 0.35 : 1

      Rectangle {
        height: parent.height
        radius: parent.radius
        width: parent.width * Math.max(0, Math.min(1, row.peak))
        color: row.host.fg
        Behavior on width { NumberAnimation { duration: 70 } }
      }
    }
  }

  HoverHandler {
    onHoveredChanged: if (hovered && row.host.dragKey === "") row.host.setCursor(row.cursor)
  }
}
