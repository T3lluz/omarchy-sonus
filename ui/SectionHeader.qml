import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Panel kit: a section title, dimmed, with an icon in front and, on the
// right, a reading or a switch for the whole section. Dim is the foreground
// mixed toward the background, so it stays dim on a light theme too.
Item {
  id: header

  property string icon: ""
  property string title: ""
  property string detail: ""
  property color detailColor: foreground
  property bool showSwitch: false
  property bool checked: false
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color background: Commons.Color.background
  property string fontFamily: Style.font.family
  readonly property color dim: Qt.tint(foreground, Qt.rgba(background.r, background.g, background.b, 0.4))

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
    color: header.dim
    fontFamily: header.fontFamily
  }

  MonoText {
    id: titleText
    anchors.left: iconBox.right
    anchors.leftMargin: iconBox.visible ? Style.space(4) : 0
    anchors.right: toggle.visible ? toggle.left : detailText.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    step: "small"
    textFormat: Text.PlainText
    elide: Text.ElideRight
    text: header.title
    color: header.dim
    fontFamily: header.fontFamily
  }

  MonoText {
    id: detailText
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    visible: !header.showSwitch && header.detail !== ""
    width: visible ? Math.min(implicitWidth, header.width * 0.6) : 0
    step: "small"
    textFormat: Text.PlainText
    text: header.detail
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideRight
    color: header.detailColor
    fontFamily: header.fontFamily
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
