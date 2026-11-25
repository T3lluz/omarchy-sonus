import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Every output or input, once a device room opens it, as small rooms on the
// same four columns as the channels below, in the devices' tone. The one in
// use is tinted deeper and carries a check in a column of its own; the rest
// are quiet. Clicking another switches to it.
Grid {
  id: list

  required property var host
  property string section: ""

  readonly property var devices: section === "" ? [] : host.devices(section)
  readonly property color tone: host.toneFor(section === "src" ? "input" : "master")
  readonly property real cellWidth: (width - columnSpacing * (columns - 1)) / columns
  // Every tile as tall as the tallest name in its row, so a long one keeps
  // its row even without stretching the others.
  property var rowNames: []
  onDevicesChanged: Qt.callLater(measure)

  function measure() {
    var rows = []
    for (var i = 0; i < picks.count; i++) {
      var pick = picks.itemAt(i)
      var r = Math.floor(i / columns)
      rows[r] = Math.max(rows[r] || 0, pick ? pick.nameHeight : 0)
    }
    rowNames = rows
  }

  function cellHeight(index) {
    return Math.max(rowNames[Math.floor(index / columns)] || 0, host.iconColumn) + Style.space(14)
  }

  columns: 4
  columnSpacing: host.roomGap
  rowSpacing: host.roomGap

  Repeater {
    id: picks
    model: list.devices

    Rectangle {
      id: pick
      required property var modelData
      required property int index
      readonly property string pickKey: list.section + ":" + modelData.name
      readonly property bool keyed: list.host.cursorActive && list.host.cursorKey === pickKey
      readonly property bool lit: list.host.cursorKey === pickKey
      readonly property bool current: !!modelData.active
      readonly property real nameHeight: pickName.implicitHeight

      width: list.cellWidth
      height: list.cellHeight(index)
      radius: Style.cornerRadius
      color: Qt.rgba(list.tone.r, list.tone.g, list.tone.b, current ? 0.17 : lit ? 0.11 : 0.065)
      border.width: keyed ? Math.max(1, Style.space(1)) : 0
      border.color: Qt.rgba(list.tone.r, list.tone.g, list.tone.b, 0.6)
      onKeyedChanged: if (keyed) list.host.ensureVisible(pick)
      // Each device's icon plays as the list opens, or as it connects; the
      // check draws in where the device in use is, and again on a switch.
      onCurrentChanged: if (current) check.start(true)
      Component.onCompleted: {
        pickIcon.play++
        if (current) check.play++
      }

      Behavior on color { ColorAnimation { duration: Style.duration(140) } }

      PixelIcon {
        id: pickIcon
        x: list.host.roomPad + Math.round((Style.font.title - width) / 2)
        anchors.verticalCenter: parent.verticalCenter
        name: Model.devicePixel(pick.modelData.form, list.section)
        size: Style.font.title
        color: pick.current || pick.lit ? list.tone : list.host.dim
        playDelay: 40 + pick.index * 60
      }

      MonoText {
        step: "body"
        fontFamily: list.host.fontFamily
        id: pickName
        anchors.left: parent.left
        anchors.leftMargin: list.host.snap(list.host.roomPad + Style.font.title + Style.space(8))
        anchors.right: check.left
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: Model.wrapName(pick.modelData.label || "Unknown", Model.monoColumns(width, advance))
        color: pick.current || pick.lit ? list.host.fg : list.host.dim
        onImplicitHeightChanged: Qt.callLater(list.measure)
        Component.onCompleted: Qt.callLater(list.measure)
      }

      // The device in use, marked as well as tinted, in a column every tile
      // keeps so the names line up.
      PixelIcon {
        id: check
        anchors.right: parent.right
        anchors.rightMargin: list.host.roomPad
        anchors.verticalCenter: parent.verticalCenter
        name: "check"
        size: Style.font.bodySmall
        color: list.tone
        opacity: pick.current ? 1 : 0
        playDelay: 240
      }

      MouseArea {
        id: pickMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: pick.current ? Qt.ArrowCursor : Qt.PointingHandCursor
        onPositionChanged: list.host.pointAt(pick.pickKey)
        onEntered: list.host.pointAt(pick.pickKey)
        onExited: if (!list.host.cursorActive && list.host.cursorKey === pick.pickKey) list.host.cursorKey = ""
        onClicked: list.host.selectDevice(list.section, pick.modelData)
      }

      PanelToolTip {
        visible: pickMouse.containsMouse && !pick.current
        text: (list.section === "sink" ? "Play through " : "Record from ") + (pick.modelData.label || "this device")
        fontFamily: list.host.fontFamily
      }
    }
  }
}
