import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Panel kit: a banner over the sections. An icon, its text in full, an
// optional button and an optional close. `tone` is "accent" or "urgent";
// while `busy` the icon turns and the buttons step aside.
BorderSurface {
  id: notice

  property string icon: ""
  property string text: ""
  property string tone: "accent"
  property string actionLabel: ""
  property bool busy: false
  property bool dismissable: false
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color urgent: Commons.Color.urgent
  property string fontFamily: Style.font.family

  signal actioned()
  signal dismissed()

  readonly property color toneColor: tone === "urgent" ? urgent : accent

  width: parent ? parent.width : implicitWidth
  radius: Style.cornerRadius
  color: Qt.rgba(toneColor.r, toneColor.g, toneColor.b, 0.12)
  borderSpec: Border.flat(Qt.rgba(toneColor.r, toneColor.g, toneColor.b, 0.45), Math.max(1, Style.normalBorderWidth))
  implicitHeight: Math.max(label.implicitHeight, actions.implicitHeight) + Style.space(14)

  Glyph {
    id: iconBox
    anchors.left: parent.left
    anchors.leftMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(22)
    icon: notice.icon
    size: Style.font.title
    color: notice.toneColor
    fontFamily: notice.fontFamily

    // Turns while something is in flight, so the banner reads as working.
    RotationAnimation on rotation {
      running: notice.busy && notice.visible
      from: 0
      to: 360
      duration: 1200
      loops: Animation.Infinite
      onStopped: iconBox.rotation = 0
    }
  }

  Text {
    id: label
    anchors.left: iconBox.right
    anchors.leftMargin: Style.space(10)
    anchors.right: actions.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    // All of it, however long: a cut-off error is no help, and the panel
    // scrolls. Long words and paths break rather than run out of the banner.
    wrapMode: Text.Wrap
    text: notice.text
    color: notice.foreground
    font.family: notice.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Row {
    id: actions
    anchors.right: parent.right
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(4)

    Button {
      id: actionButton
      anchors.verticalCenter: parent.verticalCenter
      visible: notice.actionLabel !== "" && !notice.busy
      text: notice.actionLabel
      fontSize: Style.font.bodySmall
      foreground: notice.foreground
      fontFamily: notice.fontFamily
      bordered: true
      onClicked: notice.actioned()
    }

    Button {
      anchors.verticalCenter: parent.verticalCenter
      visible: notice.dismissable && !notice.busy
      iconText: "󰅖"
      iconSize: Style.font.body
      tooltipText: "Hide"
      foreground: notice.foreground
      fontFamily: notice.fontFamily
      onClicked: notice.dismissed()
    }
  }
}
