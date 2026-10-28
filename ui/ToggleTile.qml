import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Panel kit: a half-width on/off tile for the bar picks. Icon, label and a
// switch, the whole tile one click target, filled while on. Two sit side by
// side under a "Show in the bar" header.
CursorSurface {
  id: tile

  property string icon: ""
  property string label: ""
  property string hint: ""
  property bool checked: false
  property string fontFamily: Style.font.family

  signal toggled()

  hasCursor: mouse.containsMouse
  current: checked
  bordered: true
  implicitHeight: Math.max(labelText.implicitHeight, toggle.implicitHeight) + Style.space(16)

  Glyph {
    id: iconBox
    anchors.left: parent.left
    anchors.leftMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(20)
    icon: tile.icon
    size: Style.font.body
    color: tile.foreground
    opacity: tile.checked ? 1 : 0.6
    fontFamily: tile.fontFamily
  }

  Text {
    id: labelText
    anchors.left: iconBox.right
    anchors.leftMargin: Style.space(8)
    anchors.right: toggle.left
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: tile.label
    color: tile.foreground
    opacity: tile.checked ? 1 : 0.8
    elide: Text.ElideRight
    font.family: tile.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  ToggleSwitch {
    id: toggle
    anchors.right: parent.right
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    trackHeight: Math.max(16, Math.round(Style.spacing.controlHeight * 0.45))
    checked: tile.checked
    interactive: false
    foreground: tile.foreground
    accent: tile.accent
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: tile.toggled()
  }

  // A label cut short in the half-width tile shows in full here.
  PanelToolTip {
    visible: mouse.containsMouse && text !== ""
    text: labelText.truncated ? tile.label + (tile.hint !== "" ? " · " + tile.hint : "") : tile.hint
    fontFamily: tile.fontFamily
  }
}
