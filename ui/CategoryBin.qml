import QtQuick

// Drop target for one category, showing its assigned apps as icon chips.
// A chip can be dragged on to another bin, or back to MASTER to unassign.
Rectangle {
  id: bin

  required property var theme
  property string key: ""
  property string label: ""
  property color accent: theme.accent
  property var apps: []
  property bool dropHover: false
  property string grabbedKey: ""
  property string hoverName: ""

  signal chipGrabMoved(string appKey, real x, real y)
  signal chipGrabReleased(string appKey, real x, real y)
  signal chipClicked(string appKey, real x, real y)

  radius: theme.cardRadius
  color: dropHover ? theme.alpha(accent, 0.14) : theme.card
  border.width: dropHover ? Math.max(1, theme.s(2)) : 0
  border.color: accent
  Behavior on color { ColorAnimation { duration: 120 } }

  readonly property real chip: theme.s(26)
  readonly property real gap: theme.s(5)
  readonly property int perRow: Math.max(1, Math.floor((width - theme.s(20) + gap) / (chip + gap)))
  readonly property int rows: Math.max(1, Math.floor((height - theme.s(34) - theme.s(6) + gap) / (chip + gap)))
  readonly property int capacity: perRow * rows
  readonly property int overflow: Math.max(0, apps.length - capacity)

  Rectangle {
    x: theme.s(12)
    y: theme.s(14)
    width: theme.s(8)
    height: width
    radius: width / 2
    color: bin.accent
  }

  Text {
    x: theme.s(26)
    y: theme.s(8)
    height: theme.s(20)
    width: bin.width - x - theme.s(30)
    verticalAlignment: Text.AlignVCenter
    elide: Text.ElideRight
    textFormat: Text.PlainText
    text: bin.hoverName !== "" ? bin.hoverName : bin.label
    color: bin.hoverName !== "" ? theme.fg : bin.accent
    font.family: theme.font
    font.pixelSize: theme.s(11)
    font.weight: Font.Bold
    font.letterSpacing: bin.hoverName !== "" ? 0 : theme.s(1)
  }

  Text {
    anchors.right: parent.right
    anchors.rightMargin: theme.s(12)
    y: theme.s(8)
    height: theme.s(20)
    verticalAlignment: Text.AlignVCenter
    visible: bin.apps.length > 0
    text: bin.overflow > 0 ? "+" + bin.overflow : bin.apps.length
    color: theme.dim
    font.family: theme.font
    font.pixelSize: theme.s(10)
  }

  Text {
    anchors.fill: parent
    anchors.topMargin: theme.s(26)
    visible: bin.apps.length === 0
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    text: bin.dropHover ? "Release to assign" : "Drop apps here"
    color: bin.dropHover ? bin.accent : theme.faint
    font.family: theme.font
    font.pixelSize: theme.s(10)
  }

  Flow {
    x: theme.s(10)
    y: theme.s(34)
    width: bin.width - theme.s(20)
    spacing: bin.gap

    Repeater {
      model: bin.apps.slice(0, bin.capacity)

      Rectangle {
        id: chipItem
        required property var modelData
        width: bin.chip
        height: bin.chip
        radius: theme.chipRadius
        color: chipMouse.containsMouse ? theme.buttonHover : theme.buttonFill
        opacity: bin.grabbedKey === modelData.key ? 0.35 : 1

        Image {
          anchors.fill: parent
          anchors.margins: theme.s(4)
          visible: status === Image.Ready
          source: chipItem.modelData.icon || ""
          sourceSize.width: width * 2
          sourceSize.height: height * 2
          smooth: true
          mipmap: true
          asynchronous: true
        }

        Text {
          anchors.centerIn: parent
          visible: !chipItem.modelData.icon
          text: String(chipItem.modelData.name || "?").charAt(0).toUpperCase()
          color: theme.fg
          font.family: theme.font
          font.pixelSize: theme.s(12)
          font.weight: Font.Bold
        }

        MouseArea {
          id: chipMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: grabbing ? Qt.ClosedHandCursor : Qt.OpenHandCursor
          property bool maybeGrab: false
          property bool grabbing: false
          property real pressX: 0
          property real pressY: 0

          function binPoint(x, y) { return chipItem.mapToItem(bin, x, y) }

          onEntered: bin.hoverName = chipItem.modelData.name
          onExited: if (bin.hoverName === chipItem.modelData.name) bin.hoverName = ""
          onPressed: function(event) {
            if (event.button === Qt.RightButton) {
              var p = binPoint(event.x, event.y)
              bin.chipClicked(chipItem.modelData.key, p.x, p.y)
              return
            }
            maybeGrab = true
            grabbing = false
            pressX = event.x
            pressY = event.y
          }
          onPositionChanged: function(event) {
            if (!maybeGrab) return
            if (!grabbing && Math.abs(event.x - pressX) + Math.abs(event.y - pressY) > 10) grabbing = true
            if (grabbing) {
              var p = binPoint(event.x, event.y)
              bin.chipGrabMoved(chipItem.modelData.key, p.x, p.y)
            }
          }
          onReleased: function(event) {
            if (!maybeGrab) return
            var p = binPoint(event.x, event.y)
            if (grabbing) bin.chipGrabReleased(chipItem.modelData.key, p.x, p.y)
            else bin.chipClicked(chipItem.modelData.key, p.x, p.y)
            maybeGrab = false
            grabbing = false
          }
          onCanceled: {
            maybeGrab = false
            grabbing = false
          }
        }
      }
    }
  }
}
