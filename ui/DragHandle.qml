import QtQuick

// Where an app can be picked up: press and move to drag it onto a channel's
// tile, or click for `tapped`.
MouseArea {
  id: handle

  required property var host
  required property string appKey
  property bool grabbing: false
  // The panel took this drag back (esc). The button is still down, so this
  // keeps the pointer from picking the app up again until it is released.
  property bool lifted: false
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
    lifted = false
  }
  onPositionChanged: function(event) {
    if (!pressed) return
    if (!grabbing && Math.abs(event.x - pressX) + Math.abs(event.y - pressY) > 8) grabbing = true
    if (!grabbing) return
    if (lifted && host.dragKey !== appKey) return
    lifted = true
    host.dragMove(appKey, handle, event.x, event.y)
  }
  onReleased: function(event) {
    if (!grabbing) tapped()
    else if (host.dragKey === appKey) host.dragRelease(appKey, handle, event.x, event.y)
    grabbing = false
  }
  onCanceled: {
    grabbing = false
    host.endDrag()
  }

  // A tile rebuilds its cards when its apps change, which can take this one
  // mid-drag, and then no release ever comes: the panel would stay in a drag.
  Component.onDestruction: if (grabbing && host) host.endDrag()
}
