import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "ui"
import "ui/Glyphs.js" as Glyphs
import "ui/Eq.js" as Eq

// The mixer: five channel faders on the left, the app mixer on the right
// (category bins beside the MASTER container of every app playing sound),
// with the per-category EQ and the settings sliding over the deck.
//
// A floating layer surface sized to the card, not a full-screen popup: like
// the desktop app it stays up while you work in other windows, moves by its
// header and remembers where it was left. Esc, the close button or the
// hotkey put it away.
Item {
  id: root

  property var service: null
  property bool open: false
  property var openedOn: null

  Theme { id: skin }

  readonly property var channelKeys: ["master", "game", "chat", "media", "aux"]
  readonly property var categories: [
    { key: "game", title: "Game", label: "GAME", color: skin.channelColor("game") },
    { key: "chat", title: "Chat", label: "CHAT", color: skin.channelColor("chat") },
    { key: "media", title: "Media", label: "MEDIA", color: skin.channelColor("media") },
    { key: "aux", title: "Aux", label: "AUX", color: skin.channelColor("aux") }
  ]

  // ---- layout ---------------------------------------------------------------

  readonly property real pad: skin.s(16)
  readonly property real headerH: skin.s(34)
  readonly property real headerGap: skin.s(12)
  readonly property real bannerH: service && service.legacy ? skin.s(46) : 0
  readonly property real deckH: skin.s(396)
  readonly property real stripW: skin.s(84)
  readonly property real stripGap: skin.s(8)
  readonly property real channelsW: 5 * stripW + 4 * stripGap
  readonly property real dividerW: skin.s(22)
  readonly property real binsW: skin.s(150)
  readonly property real binsGap: skin.s(8)
  readonly property real masterPad: skin.s(10)
  readonly property real masterLabelH: skin.s(34)
  readonly property real scrollH: skin.s(14)
  readonly property int appCount: service ? service.appsModel.count : 0
  readonly property real screenW: win.screen ? win.screen.width : 1280
  readonly property real screenH: win.screen ? win.screen.height : 800
  readonly property real edge: Math.max(Style.gapsOut, skin.s(8))
  readonly property real chrome: pad * 2 + channelsW + dividerW + binsW + binsGap + masterPad * 2
  readonly property real maxInner: Math.max(stripW, screenW - edge * 2 - chrome)
  readonly property real masterInner: {
    if (appCount <= 0) return Math.min(skin.s(210), maxInner)
    var needed = appCount * stripW + (appCount - 1) * stripGap
    if (needed <= maxInner) return needed
    var n = Math.max(1, Math.floor((maxInner + stripGap) / (stripW + stripGap)))
    return n * stripW + (n - 1) * stripGap
  }
  readonly property real masterW: masterInner + masterPad * 2
  readonly property real cardW: chrome + masterInner
  readonly property real cardH: pad * 2 + headerH + headerGap + bannerH + deckH
  readonly property real deckW: cardW - pad * 2
  readonly property real appsX: channelsW + dividerW

  property real posX: 0
  property real posY: 0

  function clampPos() {
    posX = Math.max(edge, Math.min(posX, screenW - cardW - edge))
    posY = Math.max(edge, Math.min(posY, screenH - cardH - edge))
  }

  onCardWChanged: clampPos()
  onCardHChanged: clampPos()

  // ---- lifecycle --------------------------------------------------------------

  function focusedScreen() {
    var monitor = Hyprland.focusedMonitor
    var name = monitor ? String(monitor.name || "") : ""
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (String(screens[i].name) === name) return screens[i]
    return screens.length ? screens[0] : null
  }

  function show() {
    if (open) return
    openedOn = focusedScreen()
    var saved = service ? service.savedPos : null
    if (saved && saved.x !== undefined && saved.y !== undefined) {
      posX = saved.x
      posY = saved.y
    } else {
      posX = (screenW - cardW) / 2
      posY = (screenH - cardH) / 2
    }
    clampPos()
    closeMenu()
    refreshBins()
    focusPrimed = false
    win.visible = true
    open = true
    primeTimer.restart()
    for (var i = 0; i < channelRepeater.count; i++) {
      var s = channelRepeater.itemAt(i)
      if (s) s.replay()
    }
    for (var j = 0; j < appRepeater.count; j++) {
      var a = appRepeater.itemAt(j)
      if (a) a.replay()
    }
    if (service) service.checkUpdate(false)
    Qt.callLater(function() { keySink.forceActiveFocus() })
  }

  function hide() {
    if (!open) return
    closeMenu()
    endDrag()
    if (drawerOpen) drawerOpen = false
    if (eqOpen) closeEq(false)
    if (service) service.persist()
    open = false
    hideTimer.restart()
  }

  function toggle() { open ? hide() : show() }

  property bool focusPrimed: false
  Timer { id: primeTimer; interval: 80; onTriggered: root.focusPrimed = true }
  Timer { id: hideTimer; interval: 170; onTriggered: if (!root.open) win.visible = false }

  function handleEscape() {
    if (menuKey !== "") closeMenu()
    else if (eqOpen) closeEq(true)
    else if (drawerOpen) drawerOpen = false
    else hide()
  }

  // ---- EQ ---------------------------------------------------------------------

  property bool eqOpen: false
  property string eqKey: ""

  function eqState(key) {
    var saved = service && service.eqs ? service.eqs[key] : null
    return Eq.normalized(saved)
  }

  function eqActive(key) {
    var st = eqState(key)
    return st.enabled && !Eq.isFlat(st)
  }

  function openEq(key) {
    var cat = null
    for (var i = 0; i < categories.length; i++) if (categories[i].key === key) cat = categories[i]
    if (!cat) return
    drawerOpen = false
    if (eqOpen && eqKey === key) {
      closeEq(true)
      return
    }
    // Switching category glides the faders from one curve to the next;
    // opening fresh spreads them out from 0 dB.
    eqPage.load(key, cat.label, cat.color, eqState(key), !eqOpen)
    eqKey = key
    eqOpen = true
  }

  function closeEq(animate) {
    if (!eqOpen) return
    eqOpen = false
    if (service) service.persist()
  }

  // ---- settings drawer -----------------------------------------------------

  property bool drawerOpen: false
  onDrawerOpenChanged: {
    if (!drawerOpen) return
    if (eqOpen) closeEq(false)
    if (service) service.checkUpdate(false)
  }

  // ---- bins -------------------------------------------------------------------

  property var binApps: ({ game: [], chat: [], media: [], aux: [] })

  function sameKeys(a, b) {
    if (!a || !b || a.length !== b.length) return false
    for (var i = 0; i < a.length; i++) if (a[i].key !== b[i].key || a[i].icon !== b[i].icon) return false
    return true
  }

  // Bins are reassigned only when their contents change, so a chip being
  // dragged is not rebuilt under the pointer by a routine snapshot.
  function refreshBins() {
    if (!service) return
    var grouped = { game: [], chat: [], media: [], aux: [] }
    var model = service.appsModel
    for (var i = 0; i < model.count; i++) {
      var row = model.get(i)
      var ch = service.effectiveChannel(row.key, row.channel)
      if (grouped[ch]) grouped[ch].push({ key: row.key, name: row.name, icon: row.icon })
    }
    var next = {}
    var changed = false
    for (var key in grouped) {
      grouped[key].sort(function(a, b) { return String(a.name).toLowerCase() < String(b.name).toLowerCase() ? -1 : 1 })
      if (sameKeys(grouped[key], binApps[key])) next[key] = binApps[key]
      else {
        next[key] = grouped[key]
        changed = true
      }
    }
    if (changed) binApps = next
  }

  Connections {
    target: root.service
    function onAppsVersionChanged() { root.refreshBins() }
    function onPendingRoutesChanged() { root.refreshBins() }
  }

  function appName(key) {
    var info = service && service.appInfo ? service.appInfo[key] : null
    return info ? info.name : key
  }

  function appIcon(key) {
    var info = service && service.appInfo ? service.appInfo[key] : null
    return info && service.iconCache[key] ? service.iconCache[key] : ""
  }

  function currentChannel(key) {
    var info = service && service.appInfo ? service.appInfo[key] : null
    return service ? service.effectiveChannel(key, info ? info.channel : "") : ""
  }

  // ---- drag and drop ------------------------------------------------------------

  property string dragKey: ""
  property string dropTarget: ""
  property real dragX: 0
  property real dragY: 0

  function targetAt(p) {
    for (var i = 0; i < binRepeater.count; i++) {
      var b = binRepeater.itemAt(i)
      var q = b.mapToItem(body, 0, 0)
      if (p.x >= q.x && p.x <= q.x + b.width && p.y >= q.y && p.y <= q.y + b.height) return b.key
    }
    var m = masterBox.mapToItem(body, 0, 0)
    if (p.x >= m.x && p.x <= m.x + masterBox.width && p.y >= m.y && p.y <= m.y + masterBox.height) return "master"
    return ""
  }

  function dragMove(key, item, x, y) {
    var p = item.mapToItem(body, x, y)
    if (dragKey !== key) {
      closeMenu()
      dragKey = key
    }
    dragX = p.x
    dragY = p.y
    dropTarget = targetAt(p)
  }

  function dragRelease(key, item, x, y) {
    var target = targetAt(item.mapToItem(body, x, y))
    var current = currentChannel(key)
    endDrag()
    if (target !== "" && target !== "master" && target !== current) service.route(key, target)
    else if (target === "master" && current !== "") service.route(key, "")
  }

  function endDrag() {
    dragKey = ""
    dropTarget = ""
  }

  // ---- route menu ---------------------------------------------------------------

  property string menuKey: ""

  function openMenu(key, item, x, y) {
    var p = item.mapToItem(body, x, y)
    menuKey = key
    routeMenu.x = Math.max(skin.s(6), Math.min(p.x, body.width - routeMenu.width - skin.s(6)))
    routeMenu.y = Math.max(skin.s(6), Math.min(p.y, body.height - routeMenu.height - skin.s(6)))
  }

  function closeMenu() { menuKey = "" }

  // ---- master container scrolling ----------------------------------------------

  function scrollBy(delta) {
    var limit = Math.max(0, appFlick.contentWidth - appFlick.width)
    if (limit <= 0) return
    appFlick.targetX = Math.max(0, Math.min(limit, appFlick.targetX - delta / 120 * skin.s(56)))
  }

  // ---- window ---------------------------------------------------------------------

  PanelWindow {
    id: win

    visible: false
    screen: root.openedOn
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: Math.ceil(root.cardW)
    implicitHeight: Math.ceil(root.cardH)

    anchors {
      top: true
      left: true
    }
    margins {
      top: Math.round(root.posY)
      left: Math.round(root.posX)
    }

    WlrLayershell.namespace: "sonus"
    WlrLayershell.layer: WlrLayer.Overlay
    // A brief Exclusive prime takes the keyboard when the hotkey opens the
    // panel; OnDemand then lets the rest of the desktop keep working.
    WlrLayershell.keyboardFocus: root.open
      ? (root.focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
      : WlrKeyboardFocus.None

    Item {
      id: body
      width: root.cardW
      height: root.cardH
      opacity: root.open ? 1 : 0
      transform: Translate { y: root.open ? 0 : skin.s(14) }
      Behavior on opacity { NumberAnimation { duration: root.open ? 190 : 150; easing.type: root.open ? Easing.OutCubic : Easing.InCubic } }

      BorderSurface {
        anchors.fill: parent
        color: Commons.Color.popups.background
        borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
        radius: skin.radius
      }

      FocusScope {
        id: keySink
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.handleEscape()
            event.accepted = true
          }
        }
      }

      // ---- header -------------------------------------------------------------

      MouseArea {
        id: headerDrag
        x: 0
        y: 0
        width: body.width
        height: root.pad + root.headerH
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.ArrowCursor
        property real pressX: 0
        property real pressY: 0
        onPressed: function(event) {
          pressX = event.x
          pressY = event.y
          keySink.forceActiveFocus()
        }
        // The surface moves under the pointer, so the offset from the press
        // point is the distance still to travel.
        onPositionChanged: function(event) {
          if (!pressed) return
          root.posX += event.x - pressX
          root.posY += event.y - pressY
          root.clampPos()
        }
        onReleased: if (root.service) root.service.savePos(root.posX, root.posY)
      }

      Row {
        x: root.pad
        y: root.pad
        height: root.headerH
        spacing: skin.s(10)

        Image {
          anchors.verticalCenter: parent.verticalCenter
          width: skin.s(24)
          height: width
          source: Qt.resolvedUrl("assets/icon.png")
          sourceSize.width: width * 2
          sourceSize.height: height * 2
          smooth: true
          mipmap: true
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "SONUS"
          color: skin.fg
          font.family: skin.font
          font.pixelSize: skin.s(16)
          font.weight: Font.Bold
          font.letterSpacing: skin.s(2)
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(0, root.channelsW - skin.s(130))
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: !root.service ? ""
            : (root.service.noticeText !== "" ? root.service.noticeText
              : (!root.service.engineUp ? "Starting…" : root.service.status))
          color: root.service && root.service.noticeError ? skin.urgent : skin.dim
          font.family: skin.font
          font.pixelSize: skin.s(10)
        }
      }

      Row {
        x: root.pad + root.appsX
        y: root.pad
        height: root.headerH
        spacing: skin.s(10)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: Glyphs.apps
          color: skin.fg
          font.family: skin.font
          font.pixelSize: skin.s(18)
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "App Mixer"
          color: skin.fg
          font.family: skin.font
          font.pixelSize: skin.s(15)
          font.weight: Font.Bold
        }
      }

      Row {
        anchors.right: parent.right
        anchors.rightMargin: root.pad
        y: root.pad + (root.headerH - height) / 2
        spacing: skin.s(8)

        IconButton {
          theme: skin
          glyph: Glyphs.cog
          active: root.drawerOpen
          badge: root.service && root.service.update.state === "outdated" && !root.service.update.busy
          onClicked: root.drawerOpen = !root.drawerOpen
        }

        IconButton {
          theme: skin
          glyph: Glyphs.close
          danger: true
          onClicked: root.hide()
        }
      }

      // ---- the desktop app is still running ---------------------------------

      Rectangle {
        visible: root.bannerH > 0
        x: root.pad
        y: root.pad + root.headerH + root.headerGap
        width: root.deckW
        height: root.bannerH - skin.s(10)
        radius: skin.chipRadius
        color: skin.alpha(skin.urgent, 0.14)
        border.width: Math.max(1, skin.s(1))
        border.color: skin.alpha(skin.urgent, 0.4)

        Text {
          x: skin.s(14)
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - takeOver.width - skin.s(40)
          elide: Text.ElideRight
          text: "The Sonus desktop app is running too. Both would fight over routing, so this panel leaves it alone until you switch."
          color: skin.fg
          font.family: skin.font
          font.pixelSize: skin.s(11)
        }

        Chip {
          id: takeOver
          theme: skin
          anchors.right: parent.right
          anchors.rightMargin: skin.s(8)
          anchors.verticalCenter: parent.verticalCenter
          text: "Switch to the plugin"
          tint: skin.urgent
          active: true
          onClicked: root.service.takeOver()
        }
      }

      // ---- deck -------------------------------------------------------------------

      Item {
        id: deck
        x: root.pad
        y: root.pad + root.headerH + root.headerGap + root.bannerH
        width: root.deckW
        height: root.deckH
        clip: true

        Repeater {
          id: channelRepeater
          model: root.channelKeys

          ChannelStrip {
            id: channelStrip
            required property var modelData
            required property int index
            readonly property var node: root.service && root.service.channels ? root.service.channels[modelData] : null
            theme: skin
            key: modelData
            x: index * (root.stripW + root.stripGap)
            width: root.stripW
            height: root.deckH
            label: modelData.toUpperCase()
            glyph: Glyphs.channel(modelData)
            accent: skin.channelColor(modelData)
            volume: node ? node.volume : 0
            muted: node ? node.muted : false
            showEq: modelData !== "master"
            eqActive: modelData !== "master" && root.service && root.eqActive(modelData)
            opacity: node ? 1 : 0.5
            onVolumeRequested: function(v) { root.service.setVolume(modelData, v) }
            onMuteRequested: function(v) { root.service.setMute(modelData, v) }
            onEqRequested: root.openEq(modelData)
          }
        }

        Rectangle {
          x: root.channelsW + root.dividerW / 2 - width / 2
          y: skin.s(96)
          width: Math.max(2, skin.s(3))
          height: root.deckH - skin.s(192)
          radius: width / 2
          color: skin.rule
        }

        // Category bins, stacked.
        Column {
          x: root.appsX
          width: root.binsW
          spacing: root.binsGap

          Repeater {
            id: binRepeater
            model: root.categories

            CategoryBin {
              id: binItem
              required property var modelData
              theme: skin
              width: root.binsW
              height: (root.deckH - 3 * root.binsGap) / 4
              key: modelData.key
              label: modelData.label
              accent: modelData.color
              apps: root.binApps[modelData.key] || []
              dropHover: root.dragKey !== "" && root.dropTarget === modelData.key
              grabbedKey: root.dragKey
              onChipGrabMoved: function(appKey, x, y) { root.dragMove(appKey, binItem, x, y) }
              onChipGrabReleased: function(appKey, x, y) { root.dragRelease(appKey, binItem, x, y) }
              onChipClicked: function(appKey, x, y) { root.openMenu(appKey, binItem, x, y) }
            }
          }
        }

        // MASTER: every app playing sound, each with its own fader.
        Rectangle {
          id: masterBox
          x: root.appsX + root.binsW + root.binsGap
          width: root.masterW
          height: root.deckH
          radius: skin.cardRadius
          readonly property bool hot: root.dragKey !== "" && root.dropTarget === "master"
          color: hot ? skin.alpha(skin.fg, 0.07) : skin.well
          border.width: hot ? Math.max(1, skin.s(2)) : Math.max(1, skin.s(1))
          border.color: hot ? skin.fg : skin.rule
          Behavior on color { ColorAnimation { duration: 120 } }

          Text {
            id: masterTitle
            x: root.masterPad + skin.s(4)
            y: skin.s(8)
            height: skin.s(20)
            verticalAlignment: Text.AlignVCenter
            text: "MASTER"
            color: skin.fg
            font.family: skin.font
            font.pixelSize: skin.s(11)
            font.weight: Font.Bold
            font.letterSpacing: skin.s(1)
          }

          Text {
            x: masterTitle.x + masterTitle.width + skin.s(12)
            y: masterTitle.y
            height: masterTitle.height
            width: masterBox.width - x - root.masterPad
            visible: width > skin.s(150)
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: "drag an app onto a category to assign it"
            color: skin.faint
            font.family: skin.font
            font.pixelSize: skin.s(10)
          }

          Column {
            anchors.centerIn: parent
            visible: root.appCount === 0
            spacing: skin.s(6)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: Glyphs.music
              color: skin.faint
              font.family: skin.font
              font.pixelSize: skin.s(30)
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "No app audio"
              color: skin.fg
              font.family: skin.font
              font.pixelSize: skin.s(12)
              font.weight: Font.DemiBold
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              width: masterBox.width - skin.s(32)
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              text: "Apps that play sound appear here."
              color: skin.dim
              font.family: skin.font
              font.pixelSize: skin.s(10)
            }
          }

          MouseArea {
            anchors.fill: parent
            onWheel: function(event) { root.scrollBy(event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x) }
          }

          Flickable {
            id: appFlick
            x: root.masterPad
            y: root.masterLabelH
            width: root.masterInner
            height: root.deckH - root.masterLabelH - root.masterPad - root.scrollH
            contentWidth: Math.max(width, root.appCount * root.stripW + Math.max(0, root.appCount - 1) * root.stripGap)
            contentHeight: height
            interactive: false
            clip: true
            property real targetX: 0
            onContentWidthChanged: targetX = Math.max(0, Math.min(targetX, contentWidth - width))
            onWidthChanged: targetX = Math.max(0, Math.min(targetX, contentWidth - width))
            contentX: targetX
            Behavior on contentX { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            Repeater {
              id: appRepeater
              model: root.service ? root.service.appsModel : null

              ChannelStrip {
                id: appStrip
                required property int index
                required property var model
                readonly property string effective: root.service ? root.service.effectiveChannel(model.key, model.channel) : model.channel
                theme: skin
                key: model.key
                volume: model.volume
                muted: model.muted
                isApp: true
                x: index * (root.stripW + root.stripGap)
                Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                width: root.stripW
                height: appFlick.height
                label: model.name
                iconSource: model.icon
                accent: effective !== "" ? skin.channelColor(effective) : skin.dim
                lifted: root.dragKey === key
                onVolumeRequested: function(v) { root.service.setVolume(key, v) }
                onMuteRequested: function(v) { root.service.setMute(key, v) }
                onMenuRequested: function(x, y) { root.openMenu(key, appStrip, x, y) }
                onGrabMoved: function(x, y) { root.dragMove(key, appStrip, x, y) }
                onGrabReleased: function(x, y) { root.dragRelease(key, appStrip, x, y) }
                onWheelOutside: function(delta) { root.scrollBy(delta) }
              }
            }
          }

          // Scrollbar, only when the apps outgrow the screen.
          Item {
            id: scrollbar
            readonly property real limit: Math.max(0, appFlick.contentWidth - appFlick.width)
            visible: limit > 0
            x: root.masterPad
            y: masterBox.height - root.scrollH - skin.s(2)
            width: root.masterInner
            height: root.scrollH

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width
              height: skin.s(4)
              radius: height / 2
              color: skin.track
            }

            Rectangle {
              readonly property real thumbW: Math.max(skin.s(28), scrollbar.width * appFlick.width / Math.max(1, appFlick.contentWidth))
              anchors.verticalCenter: parent.verticalCenter
              x: (scrollbar.width - thumbW) * (scrollbar.limit > 0 ? appFlick.contentX / scrollbar.limit : 0)
              width: thumbW
              height: barMouse.containsMouse || barMouse.pressed ? skin.s(8) : skin.s(6)
              radius: height / 2
              color: barMouse.containsMouse || barMouse.pressed ? skin.fg : skin.dim
            }

            MouseArea {
              id: barMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              function seek(x) {
                var thumb = Math.max(skin.s(28), scrollbar.width * appFlick.width / Math.max(1, appFlick.contentWidth))
                var ratio = (x - thumb / 2) / Math.max(1, scrollbar.width - thumb)
                appFlick.targetX = Math.max(0, Math.min(scrollbar.limit, ratio * scrollbar.limit))
              }
              onPressed: function(event) { seek(event.x) }
              onPositionChanged: function(event) { if (pressed) seek(event.x) }
            }
          }
        }

        // ---- EQ page, dropping over the deck --------------------------------

        EqPage {
          id: eqPage
          theme: skin
          width: root.deckW
          height: root.deckH
          y: root.eqOpen ? 0 : -skin.s(22)
          opacity: root.eqOpen ? 1 : 0
          visible: opacity > 0.01
          enabled: root.eqOpen
          Behavior on y { NumberAnimation { duration: 240; easing.type: root.eqOpen ? Easing.OutCubic : Easing.InCubic } }
          Behavior on opacity { NumberAnimation { duration: 220 } }
          onEdited: function(key, state) { root.service.setEq(key, state) }
          onBack: root.closeEq(true)

          // Catch stray clicks so they do not reach the faders beneath.
          MouseArea { anchors.fill: parent; z: -1 }
        }

        SettingsDrawer {
          id: drawer
          theme: skin
          width: Math.min(skin.s(300), root.deckW)
          height: root.deckH
          x: root.drawerOpen ? root.deckW - width : root.deckW + skin.s(8)
          visible: x < root.deckW
          Behavior on x { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } }
          manageGraph: root.service ? root.service.manageGraph : true
          versionText: root.service
            ? "Sonus " + root.service.version
              + (root.service.update.local ? " · " + String(root.service.update.local).substring(0, 7) : "")
            : ""
          updateState: root.service ? root.service.update.state || "unknown" : "unknown"
          updateBusy: root.service ? root.service.update.busy === true : false
          updateApplying: root.service ? root.service.update.applying === true : false
          onCloseRequested: root.drawerOpen = false
          onManageGraphToggled: function(value) { root.service.setManageGraph(value) }
          onUpdateClicked: root.service.updateClicked()
        }
      }

      // ---- overlays above everything ------------------------------------------

      MouseArea {
        anchors.fill: parent
        visible: root.menuKey !== ""
        acceptedButtons: Qt.AllButtons
        onPressed: root.closeMenu()
      }

      RouteMenu {
        id: routeMenu
        theme: skin
        visible: root.menuKey !== ""
        appName: root.menuKey !== "" ? root.appName(root.menuKey) : ""
        current: root.menuKey !== "" ? root.currentChannel(root.menuKey) : ""
        effectsRunning: root.service ? root.service.effectsRunning : false
        categories: root.categories
        onPicked: function(channel) {
          var key = root.menuKey
          root.closeMenu()
          if (channel !== root.currentChannel(key)) root.service.route(key, channel)
        }
      }

      // Chip following the pointer while an app is dragged.
      Rectangle {
        visible: root.dragKey !== ""
        x: root.dragX + skin.s(14)
        y: root.dragY - height / 2
        width: ghostRow.implicitWidth + skin.s(22)
        height: skin.s(36)
        radius: skin.cardRadius
        color: skin.mix(skin.bg, skin.fg, 0.12)
        border.width: Math.max(1, skin.s(1))
        border.color: root.dropTarget !== "" && root.dropTarget !== "master"
          ? skin.channelColor(root.dropTarget) : skin.alpha(skin.fg, 0.25)
        opacity: 0.96

        Row {
          id: ghostRow
          anchors.centerIn: parent
          spacing: skin.s(8)

          Image {
            anchors.verticalCenter: parent.verticalCenter
            width: skin.s(20)
            height: width
            visible: source !== "" && status === Image.Ready
            source: root.dragKey !== "" ? root.appIcon(root.dragKey) : ""
            sourceSize.width: width * 2
            sourceSize.height: height * 2
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.dragKey !== "" ? root.appName(root.dragKey) : ""
            color: skin.fg
            font.family: skin.font
            font.pixelSize: skin.s(11)
            font.weight: Font.DemiBold
          }
        }
      }
    }
  }
}
