import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Glyphs.js" as Glyphs

// Every output or input, once a device tile opens it, as small tiles on the
// same four columns as the channels below: each icon sits over a channel's icon
// and each name over its name. The way Omarchy's network panel offers its DNS
// and Wi-Fi band choices, the one in use is filled and the rest are quiet.
// Clicking another switches to it.
Grid {
  id: list

  required property var host
  property string section: ""

  readonly property var devices: section === "" ? [] : host.devices(section)
  readonly property real cellWidth: (width - columnSpacing * (columns - 1)) / columns
  // Every tile as tall as the tallest name, so a long one keeps the rows even.
  property real tallestName: 0
  onDevicesChanged: Qt.callLater(measure)

  function measure() {
    var tallest = 0
    for (var i = 0; i < picks.count; i++) {
      var pick = picks.itemAt(i)
      if (pick) tallest = Math.max(tallest, pick.nameHeight)
    }
    tallestName = tallest
  }

  readonly property real cellHeight: Math.max(tallestName, host.iconCol) + Style.space(6)

  columns: 4
  columnSpacing: host.tileGap
  rowSpacing: host.tileGap

  Repeater {
    id: picks
    model: list.devices

    CursorSurface {
      id: pick
      required property var modelData
      readonly property string pickKey: list.section + ":" + modelData.name
      readonly property bool keyed: list.host.cursorActive && list.host.cursorKey === pickKey
      readonly property real nameHeight: pickName.implicitHeight

      width: list.cellWidth
      height: list.cellHeight
      onKeyedChanged: if (keyed) list.host.ensureVisible(pick)

      // From the panel's one cursor, not the tile's own hover, so the pointer
      // and the keyboard never light two at once.
      hasCursor: list.host.cursorKey === pickKey
      current: !!modelData.active
      foreground: list.host.fg
      color: hasCursor ? fill : current ? currentFill : Style.normalFillFor(foreground, accent)

      Text {
        id: pickIcon
        x: list.host.tilePad
        width: list.host.iconCol
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: Glyphs.deviceGlyph(pick.modelData.form)
        color: pick.current || pick.hasCursor ? list.host.fg : list.host.dim
        font.family: list.host.fontFamily
        font.pixelSize: Style.font.title
      }

      Text {
        id: pickName
        anchors.left: pickIcon.right
        anchors.leftMargin: Style.space(4)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: pick.modelData.label || "Unknown"
        color: pick.current || pick.hasCursor ? list.host.fg : list.host.dim
        font.family: list.host.fontFamily
        font.pixelSize: Style.font.body
        font.bold: pick.current
        onImplicitHeightChanged: Qt.callLater(list.measure)
        Component.onCompleted: Qt.callLater(list.measure)
      }

      MouseArea {
        id: pickMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: pick.modelData.active ? Qt.ArrowCursor : Qt.PointingHandCursor
        onPositionChanged: list.host.pointAt(pick.pickKey)
        onEntered: list.host.pointAt(pick.pickKey)
        onExited: if (!list.host.cursorActive && list.host.cursorKey === pick.pickKey) list.host.cursorKey = ""
        onClicked: list.host.selectDevice(list.section, pick.modelData)
      }

      PanelToolTip {
        visible: pickMouse.containsMouse && !pick.modelData.active
        text: (list.section === "sink" ? "Play through " : "Record from ") + (pick.modelData.label || "this device")
        fontFamily: list.host.fontFamily
      }
    }
  }
}
