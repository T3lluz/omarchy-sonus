import QtQuick
import qs.Commons
import qs.Commons as Commons

// Panel kit: a level bar. A track, a fill for `level` (0 to 100) and an
// optional marker, such as a charge limit, dimmed toward the background so it
// stays dim on a light theme.
Rectangle {
  id: levelBar

  property real level: 0
  property color fill: Commons.Color.foreground
  property color track: Qt.rgba(fill.r, fill.g, fill.b, 0.12)
  property color background: Commons.Color.background
  property color markerColor: Qt.tint(Commons.Color.foreground, Qt.rgba(background.r, background.g, background.b, 0.4))
  property real marker: 0

  height: Math.max(4, Style.space(5))
  radius: Style.cornerRadius > 0 ? height / 2 : 0
  color: track

  Rectangle {
    width: Math.max(levelBar.level > 0 ? parent.height : 0, parent.width * Math.max(0, Math.min(100, levelBar.level || 0)) / 100)
    height: parent.height
    radius: parent.radius
    color: levelBar.fill
    Behavior on width { NumberAnimation { duration: Style.duration(300); easing.type: Easing.OutCubic } }
  }

  Rectangle {
    visible: levelBar.marker > 0 && levelBar.marker < 100
    x: levelBar.width * levelBar.marker / 100 - width / 2
    anchors.verticalCenter: parent.verticalCenter
    width: Math.max(2, Style.space(2))
    height: parent.height + Style.space(6)
    radius: Style.cornerRadius > 0 ? width / 2 : 0
    color: levelBar.markerColor
  }
}
