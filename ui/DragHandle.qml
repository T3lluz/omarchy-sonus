import QtQuick

// Where an app can be picked up: press and move to drag it onto a channel
// or the output, or click for `tapped`. An app's row and its face on a
// channel strip both carry one.
MouseArea {
  id: handle

  required property var host
  required property string appKey
  property bool grabbing: false
  property real pressX: 0
  property real pressY: 0

  signal tapped()

  hoverEnabled: true
  preventStealing: true
  cursorShape: grabbing ? Qt.ClosedHandCursor : Qt.OpenHandCursor

  onPressed: function(event) {
    pressX = event.x
    pressY = event.y
    grabbing = false
  }
  onPositionChanged: function(event) {
    if (!pressed) return
    if (!grabbing && Math.abs(event.x - pressX) + Math.abs(event.y - pressY) > 8) grabbing = true
    if (grabbing) host.dragMove(appKey, handle, event.x, event.y)
  }
  onReleased: function(event) {
    if (grabbing) host.dragRelease(appKey, handle, event.x, event.y)
    else tapped()
    grabbing = false
  }
  onCanceled: {
    grabbing = false
    host.endDrag()
  }
}
