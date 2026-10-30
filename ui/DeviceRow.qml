import QtQuick
import qs.Commons
import qs.Ui
import "Glyphs.js" as Glyphs

// One output or input, as the panel kit's option row. Clicking it selects
// that device for the system. For an output, the engine also loads the
// volume and equalizer saved for it. The device in use carries a chevron
// that opens the rest of the list.
OptionRow {
  id: row

  required property var host
  required property string section
  // Set by the repeater. The row is one device from that list.
  required property var modelData
  readonly property var device: modelData || ({})

  readonly property string cursor: section + ":" + (device.name || "")
  readonly property bool expandable: !!device.active && host.devices(section).length > 1

  visible: host.deviceShown(section, device)
  // The panel's one cursor follows the pointer, so hover alone never lights a row.
  hoverLights: false
  keyboardCursor: host.cursorActive && host.cursorKey === cursor
  current: !!device.active
  foreground: host.fg
  fontFamily: host.fontFamily
  icon: Glyphs.deviceGlyph(device.form)
  title: device.label || "Unknown"
  // Each output keeps its own volume and EQ; the one in use says so.
  subtitle: section === "sink" && device.active ? host.profileLine : ""
  mark: !device.active ? "" : (!expandable ? Glyphs.check : (host.devicesOpen(section) ? Glyphs.chevronUp : Glyphs.chevronDown))
  height: implicitHeight
  onHasCursorChanged: if (hasCursor) host.ensureVisible(row)
  onHoveredChanged: if (hovered) host.setCursor(row.cursor)
  onClicked: host.selectDevice(section, device)
}
