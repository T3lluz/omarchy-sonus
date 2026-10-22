import QtQuick
import "Glyphs.js" as Glyphs

// One vertical fader with icon, label, percentage and mute button.
//
// App strips (inside the MASTER container) are also grab handles: off the
// fader, a press becomes a drag onto a category bin, or, if it never moves,
// a click opening the route menu. Volume reacts only on the fader itself, so
// grabbing the card never jumps the level.
Item {
  id: strip

  required property var theme
  property string key: ""
  property string label: ""
  property string glyph: ""
  property string iconSource: ""
  property color accent: theme.accent
  property real volume: 1
  property bool muted: false
  property bool isApp: false
  property bool showEq: false
  property bool eqActive: false
  property bool lifted: false

  signal volumeRequested(real value)
  signal muteRequested(bool value)
  signal eqRequested()
  signal menuRequested(real x, real y)
  signal grabMoved(real x, real y)
  signal grabReleased(real x, real y)
  signal wheelOutside(int delta)

  // ---- state ------------------------------------------------------------

  property bool dragging: false
  property real local: volume
  property bool muteLocal: muted
  // A snapshot taken just before a local change landed still carries the old
  // value; honouring it would bounce the fader. Hold the local value until
  // the poller has had time to see the change.
  readonly property bool holding: holdTimer.running
  readonly property bool effMuted: muteHold.running ? muteLocal : muted
  readonly property real target: (dragging || holding) ? local : (effMuted ? 0 : volume)
  property real shown: 0
  property bool instant: false
  property real wheelAcc: 0

  onTargetChanged: shown = target
  Component.onCompleted: shown = target
  Behavior on shown {
    enabled: !strip.instant && !strip.dragging
    NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
  }

  // The panel opening replays every fader rising from zero.
  function replay() {
    instant = true
    shown = 0
    instant = false
    shown = target
  }

  Timer { id: holdTimer; interval: 1400 }
  Timer { id: muteHold; interval: 1500 }

  function requestMute(value) {
    muteLocal = value
    muteHold.restart()
    muteRequested(value)
  }

  function setLevel(value) {
    local = Math.max(0, Math.min(1, value))
    holdTimer.restart()
    volumeRequested(local)
  }

  // ---- geometry -----------------------------------------------------------

  readonly property real iconSize: theme.s(isApp ? 30 : 26)
  readonly property real iconY: theme.s(16)
  readonly property real labelY: iconY + iconSize + theme.s(7)
  readonly property real pctY: labelY + theme.s(17)
  readonly property real faderTop: pctY + theme.s(32)
  readonly property real muteSize: theme.s(32)
  readonly property real muteY: height - theme.s(14) - muteSize
  readonly property real faderBot: muteY - theme.s(24)
  readonly property real trackW: theme.s(isApp ? 6 : 7)
  readonly property bool live: dragging || mouse.inFaderHover
  readonly property real thumbW: theme.s(18) + (live ? theme.s(3) : 0)
  readonly property real thumbH: theme.s(28) + (live ? theme.s(4) : 0)
  readonly property real cx: width / 2
  readonly property real thumbY: faderBot - (faderBot - faderTop) * shown

  function inFader(x, y) {
    var half = Math.max(theme.s(21), trackW) / 2 + theme.s(10)
    var grip = theme.s(16)
    return x >= cx - half && x <= cx + half && y >= faderTop - grip && y <= faderBot + grip
  }

  function valueAt(y) {
    return Math.max(0, Math.min(1, 1 - (y - faderTop) / Math.max(1, faderBot - faderTop)))
  }

  opacity: lifted ? 0.4 : 1
  Behavior on opacity { NumberAnimation { duration: 140 } }

  // ---- card ---------------------------------------------------------------

  Rectangle {
    anchors.fill: parent
    radius: theme.cardRadius
    color: mouse.containsMouse && strip.isApp && !strip.dragging ? theme.cardHover : theme.card
    Behavior on color { ColorAnimation { duration: 140 } }
  }

  Item {
    id: iconBox
    x: strip.cx - width / 2
    y: strip.iconY
    width: strip.iconSize
    height: strip.iconSize
    opacity: strip.effMuted ? 0.45 : 1

    Image {
      id: appIcon
      anchors.fill: parent
      visible: strip.iconSource !== "" && status === Image.Ready
      source: strip.iconSource
      sourceSize.width: width * 2
      sourceSize.height: height * 2
      smooth: true
      mipmap: true
      asynchronous: true
    }

    Text {
      anchors.centerIn: parent
      visible: !appIcon.visible
      text: strip.glyph !== "" ? strip.glyph : Glyphs.app
      color: strip.effMuted ? theme.dim : (strip.isApp ? theme.fg : strip.accent)
      font.family: theme.font
      font.pixelSize: strip.iconSize * 0.86
    }
  }

  Text {
    x: theme.s(8)
    width: strip.width - theme.s(16)
    y: strip.labelY
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideRight
    textFormat: Text.PlainText
    text: strip.label
    color: strip.effMuted ? theme.dim : (strip.isApp ? theme.fg : strip.accent)
    font.family: theme.font
    font.pixelSize: theme.s(strip.isApp ? 11 : 12)
    font.weight: Font.Bold
    font.letterSpacing: strip.isApp ? 0 : theme.s(1)
  }

  Text {
    width: strip.width
    y: strip.pctY
    horizontalAlignment: Text.AlignHCenter
    text: Math.round(strip.shown * 100) + "%"
    color: theme.dim
    font.family: theme.font
    font.pixelSize: theme.s(11)
  }

  // ---- fader --------------------------------------------------------------

  Rectangle {
    id: track
    x: strip.cx - width / 2
    y: strip.faderTop
    width: strip.trackW
    height: strip.faderBot - strip.faderTop
    radius: width / 2
    color: theme.track
  }

  // Soft glow under the level, a little wider than the track.
  Rectangle {
    x: strip.cx - width / 2
    y: strip.thumbY
    width: strip.trackW * 2.6
    height: Math.max(0, strip.faderBot - strip.thumbY + strip.trackW * 0.8)
    radius: width / 2
    visible: !strip.effMuted && height > width
    color: theme.alpha(strip.accent, 0.13)
  }

  Rectangle {
    x: strip.cx - width / 2
    y: strip.thumbY
    width: strip.trackW
    height: Math.max(0, strip.faderBot - strip.thumbY)
    radius: width / 2
    color: strip.effMuted ? theme.faint : strip.accent
    Behavior on color { ColorAnimation { duration: 160 } }
  }

  Rectangle {
    x: strip.cx - width / 2
    y: strip.thumbY - height / 2 + theme.s(1.5)
    width: strip.thumbW
    height: strip.thumbH
    radius: Math.min(width, height) / 2
    color: Qt.rgba(0, 0, 0, theme.light ? 0.12 : 0.35)
  }

  Rectangle {
    id: thumb
    x: strip.cx - width / 2
    y: strip.thumbY - height / 2
    width: strip.thumbW
    height: strip.thumbH
    radius: Math.min(width, height) / 2
    color: theme.thumb
    Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    Rectangle {
      anchors.centerIn: parent
      width: theme.s(9)
      height: Math.max(2, theme.s(2.5))
      radius: height / 2
      color: strip.effMuted ? theme.faint : strip.accent
    }
  }

  // ---- input --------------------------------------------------------------

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    property bool maybeGrab: false
    property bool grabbing: false
    property real pressX: 0
    property real pressY: 0
    property bool inFaderHover: false

    cursorShape: strip.dragging || inFaderHover ? Qt.PointingHandCursor
      : (strip.isApp ? (grabbing ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor)

    onPressed: function(event) {
      if (event.button === Qt.RightButton) {
        if (strip.isApp) strip.menuRequested(event.x, event.y)
        return
      }
      if (strip.inFader(event.x, event.y)) {
        if (strip.effMuted) strip.requestMute(false)
        strip.dragging = true
        strip.setLevel(strip.valueAt(event.y))
        return
      }
      if (strip.isApp) {
        maybeGrab = true
        grabbing = false
        pressX = event.x
        pressY = event.y
      }
    }

    onPositionChanged: function(event) {
      inFaderHover = strip.inFader(event.x, event.y)
      if (strip.dragging) {
        strip.setLevel(strip.valueAt(event.y))
        return
      }
      if (maybeGrab) {
        if (!grabbing && Math.abs(event.x - pressX) + Math.abs(event.y - pressY) > 10) grabbing = true
        if (grabbing) strip.grabMoved(event.x, event.y)
      }
    }

    onReleased: function(event) {
      if (strip.dragging) {
        strip.dragging = false
        strip.setLevel(strip.valueAt(event.y))
        return
      }
      if (maybeGrab) {
        if (grabbing) strip.grabReleased(event.x, event.y)
        else strip.menuRequested(event.x, event.y)
      }
      maybeGrab = false
      grabbing = false
    }

    onCanceled: {
      strip.dragging = false
      maybeGrab = false
      grabbing = false
    }

    onExited: inFaderHover = false

    onWheel: function(event) {
      if (!strip.inFader(event.x, event.y)) {
        if (strip.isApp) strip.wheelOutside(event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x)
        else event.accepted = false
        return
      }
      strip.wheelAcc += event.angleDelta.y
      var steps = strip.wheelAcc > 0 ? Math.floor(strip.wheelAcc / 120) : Math.ceil(strip.wheelAcc / 120)
      if (steps === 0) return
      strip.wheelAcc -= steps * 120
      if (strip.effMuted) strip.requestMute(false)
      var base = (strip.holding || strip.dragging) ? strip.local : strip.volume
      strip.setLevel(base + steps * 0.04)
    }
  }

  // ---- buttons (above the strip's own mouse area) ------------------------

  Rectangle {
    id: muteButton
    x: strip.cx - width / 2
    y: strip.muteY
    width: strip.muteSize
    height: strip.muteSize
    radius: width / 2
    color: strip.effMuted
      ? theme.alpha(theme.urgent, muteMouse.containsMouse ? 0.34 : 0.22)
      : (muteMouse.containsMouse ? theme.buttonHover : theme.buttonFill)
    Behavior on color { ColorAnimation { duration: 140 } }

    Text {
      anchors.centerIn: parent
      text: strip.effMuted ? Glyphs.volumeOff : Glyphs.volumeHigh
      color: strip.effMuted ? theme.mix(theme.urgent, theme.fg, 0.25) : theme.fg
      font.family: theme.font
      font.pixelSize: theme.s(15)
    }

    MouseArea {
      id: muteMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: strip.requestMute(!strip.effMuted)
    }
  }

  Rectangle {
    visible: strip.showEq
    width: theme.s(24)
    height: width
    x: strip.width - width - theme.s(7)
    y: theme.s(7)
    radius: theme.chipRadius
    color: eqMouse.containsMouse ? theme.buttonHover : (strip.eqActive ? theme.alpha(strip.accent, 0.16) : "transparent")
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
      anchors.centerIn: parent
      text: Glyphs.sliders
      color: strip.eqActive || eqMouse.containsMouse ? strip.accent : theme.faint
      font.family: theme.font
      font.pixelSize: theme.s(14)
    }

    MouseArea {
      id: eqMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: strip.eqRequested()
    }
  }
}
