import QtQuick
import qs.Commons
import qs.Ui
import "Glyphs.js" as Glyphs

// One output or input. Clicking it selects that device for the system.
// For an output, the engine also loads the volume and equalizer saved for it.
// The device in use carries a chevron that opens the rest of the list.
CursorSurface {
  id: row

  required property var host
  required property string section
  // Set by the repeater. The row is one device from that list.
  required property var modelData
  readonly property var device: modelData || ({})

  readonly property string cursor: section + ":" + (device.name || "")
  readonly property bool expandable: !!device.active && host.devices(section).length > 1

  visible: host.deviceShown(section, device)
  hasCursor: host.cursorActive && host.cursorKey === cursor
  current: !!device.active
  foreground: host.fg
  fill: host.hoverFill
  currentFill: host.selectedFill
  implicitHeight: line.implicitHeight + Style.spacing.xl
  height: implicitHeight
  onHasCursorChanged: if (hasCursor) host.ensureVisible(row)

  Row {
    id: line
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(6)
    anchors.rightMargin: Style.space(6)
    spacing: Style.space(8)

    Text {
      width: Style.space(22)
      horizontalAlignment: Text.AlignHCenter
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: Glyphs.deviceGlyph(row.device.form)
      color: row.host.fg
      font.family: row.host.fontFamily
      font.pixelSize: Style.font.title
    }

    Text {
      width: parent.width - Style.space(22) - Style.space(8) - mark.width - Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: row.device.label || "Unknown"
      color: row.host.fg
      font.family: row.host.fontFamily
      font.pixelSize: Style.font.body
      font.bold: !!row.device.active
      elide: Text.ElideRight
    }

    Text {
      id: mark
      width: Style.space(16)
      horizontalAlignment: Text.AlignRight
      anchors.verticalCenter: parent.verticalCenter
      visible: !!row.device.active
      textFormat: Text.PlainText
      text: !row.expandable ? Glyphs.check : (row.host.devicesOpen(row.section) ? Glyphs.chevronUp : Glyphs.chevronDown)
      color: row.host.dim
      font.family: row.host.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: if (containsMouse) host.setCursor(row.cursor)
    onClicked: host.selectDevice(row.section, row.device)
  }
}
