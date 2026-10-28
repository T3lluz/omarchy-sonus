import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Panel kit: a section title in Omarchy's panel style (bold small caps,
// dimmed) with an icon in front and, on the right, a reading or a switch for
// the whole section.
Item {
  id: header

  property string icon: ""
  property string title: ""
  property string detail: ""
  property color detailColor: Qt.darker(foreground, 1.15)
  property bool showSwitch: false
  property bool checked: false
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family

  signal toggled()

  width: parent ? parent.width : implicitWidth
  implicitHeight: Math.max(titleText.implicitHeight, toggle.visible ? toggle.implicitHeight : 0, detailText.implicitHeight)

  Glyph {
    id: iconBox
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    visible: header.icon !== ""
    width: visible ? Style.space(20) : 0
    icon: header.icon
    size: Style.font.body
    color: Qt.darker(header.foreground, 1.4)
    fontFamily: header.fontFamily
  }

  PanelSectionHeader {
    id: titleText
    anchors.left: iconBox.right
    anchors.leftMargin: iconBox.visible ? Style.space(4) : 0
    anchors.right: toggle.visible ? toggle.left : detailText.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    elide: Text.ElideRight
    text: header.title
    foreground: header.foreground
    fontFamily: header.fontFamily
  }

  Text {
    id: detailText
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    visible: !header.showSwitch && header.detail !== ""
    width: visible ? Math.min(implicitWidth, header.width * 0.6) : 0
    textFormat: Text.PlainText
    text: header.detail
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideRight
    color: header.detailColor
    font.family: header.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  ToggleSwitch {
    id: toggle
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    visible: header.showSwitch
    checked: header.checked
    foreground: header.foreground
    accent: header.accent
    onToggled: header.toggled()
  }
}
