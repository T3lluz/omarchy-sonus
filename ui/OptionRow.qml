import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Panel kit: one choice in a list, drawn like the device rows in Omarchy's
// own panels. Icon, name and a short description, a reading or a mark (a
// check, a chevron) at the end, filled when it is the current one.
CursorSurface {
  id: row

  property string icon: ""
  // Drawn in place of `icon` when set.
  property Component iconComponent: null
  property string title: ""
  property string subtitle: ""
  property string detail: ""
  property string mark: ""
  property string fontFamily: Style.font.family
  // Set by a panel that walks rows with the keyboard.
  property bool keyboardCursor: false
  // For a panel whose keyboard cursor follows the pointer: it turns
  // `hoverLights` off and moves its cursor on `hovered`, so only one row is
  // ever lit.
  readonly property alias hovered: mouse.containsMouse
  property bool hoverLights: true

  signal clicked()

  hasCursor: (hoverLights && mouse.containsMouse) || keyboardCursor
  implicitHeight: inner.implicitHeight + Style.spacing.xl

  Row {
    id: inner
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(10)
    spacing: Style.space(10)

    Item {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(22)
      height: Style.font.title

      Glyph {
        visible: !row.iconComponent
        anchors.centerIn: parent
        icon: row.icon
        size: Style.font.title
        color: row.foreground
        fontFamily: row.fontFamily
      }

      Loader {
        anchors.centerIn: parent
        sourceComponent: row.iconComponent
      }
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - Style.space(22) - parent.spacing * 2 - trailing.width
      spacing: Style.space(1)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: row.title
        color: row.foreground
        elide: Text.ElideRight
        font.family: row.fontFamily
        font.pixelSize: Style.font.body
        font.bold: row.current
      }

      Text {
        width: parent.width
        visible: row.subtitle !== ""
        textFormat: Text.PlainText
        text: row.subtitle
        color: row.foreground
        opacity: 0.55
        elide: Text.ElideRight
        font.family: row.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Row {
      id: trailing
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: row.detail !== ""
        textFormat: Text.PlainText
        text: row.detail
        color: row.foreground
        opacity: 0.7
        font.family: row.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Glyph {
        anchors.verticalCenter: parent.verticalCenter
        visible: row.mark !== ""
        icon: row.mark
        size: Style.font.body
        color: row.foreground
        opacity: 0.6
        fontFamily: row.fontFamily
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: row.clicked()
  }
}
