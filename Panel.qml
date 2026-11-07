import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "ui"
import "ui/Audio.js" as Audio
import "ui/Glyphs.js" as Glyphs
import "ui/Eq.js" as Eq

// Sonus in the bar. The mark drops the panel: the output and input in use,
// then one tile per channel holding the apps that play into it. Dragging an
// app's card to another tile moves it there. Picking an output also brings
// back that device's volume and equalizer. All state lives in the service;
// this only draws it.
Panel {
  id: root
  moduleName: "io.github.t3lluz.sonus"
  manageIpc: false

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null

  readonly property color fg: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(fg, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Every tile is laid out from these, and they are Omarchy's own: a 22 px
  // column for icons and mute buttons, the width its audio panel gives a
  // percent. The mixer is wider than Omarchy's 380 so the four channels fit
  // side by side, each about as wide as half an official panel row.
  readonly property real mixerWidth: Style.space(780)
  readonly property real tileGap: Style.space(6)
  readonly property real tilePad: Style.space(8)
  readonly property real iconCol: Style.space(22)
  readonly property real percentW: Style.space(30)

  readonly property int appCount: service ? service.appsModel.count : 0

  readonly property var categories: [
    { key: "game", title: "Game" },
    { key: "chat", title: "Chat" },
    { key: "media", title: "Media" },
    { key: "aux", title: "Aux" }
  ]
  // Only channels that exist can be chosen, the same as a drop.
  readonly property var routeOptions: {
    var live = service && service.channels ? service.channels : ({})
    var options = categories.filter(function(c) { return !!live[c.key] })
      .map(function(c) { return { value: c.key, label: c.title } })
    options.push({ value: "", label: "No channel" })
    return options
  }

  readonly property string dragName: {
    if (dragKey === "" || !service) return ""
    var info = service.appInfo[dragKey]
    return info ? info.name : dragKey
  }

  function channelTitle(key) {
    for (var i = 0; i < categories.length; i++) if (categories[i].key === key) return categories[i].title
    return "No channel"
  }

  // ---- the hero's caption --------------------------------------------------------

  // The official panels' changing text: one caps line under the title. What is
  // happening right now wins, then a short confirmation of what just happened;
  // otherwise it takes turns with the facts, at the panels' own pace.
  property int phraseIndex: 0
  property real captionOpacity: 1
  property string announced: ""

  function announce(line) {
    announced = line
    announcedTimer.restart()
  }

  Timer {
    id: announcedTimer
    interval: 2800
    onTriggered: root.announced = ""
  }

  readonly property var eqOnTitles: {
    var titles = []
    var live = service && service.channels ? service.channels : ({})
    for (var i = 0; i < categories.length; i++)
      if (live[categories[i].key] && eqActive(categories[i].key)) titles.push(categories[i].title)
    return titles
  }

  readonly property var heroPhrases: {
    var s = service
    if (!s) return ["Starting"]
    return Audio.heroPhrases({
      apps: appCount,
      output: s.outputLabel,
      volume: s.masterVolume,
      muted: s.masterMuted,
      eqOn: eqOnTitles,
      inputMuted: hasInput && s.mutedOf("input"),
      channelsOn: !!(s.channels && s.channels.game)
    })
  }

  readonly property bool captionHeld: dragKey !== "" || announced !== "" || outputTile.sliding
    || menuKey !== "" || openDevices !== ""

  readonly property string heroLine: {
    var s = service
    if (!s || !s.engineUp) return "Starting"
    if (dragKey !== "") return dropTarget !== ""
      ? Audio.dropLine(dragName, channelTitle(dropTarget === "master" ? "" : dropTarget))
      : Audio.movingLine(dragName)
    if (announced !== "") return announced
    if (openDevices !== "") return openDevices === "sink" ? "Pick an output" : "Pick an input"
    // The picker's icons take no keyboard focus, so its keys are said here.
    if (menuKey !== "") return "Pick a channel, or press 0 to 4"
    if (outputTile.sliding) return Audio.volumeName(outputTile.level, s.masterMuted)
    var list = heroPhrases
    return list[phraseIndex % list.length]
  }

  Timer {
    interval: 2800
    running: root.opened && root.view === "mixer" && !root.captionHeld && root.heroPhrases.length > 1
    repeat: true
    onTriggered: captionSwap.restart()
  }

  SequentialAnimation {
    id: captionSwap
    PropertyAnimation {
      target: root; property: "captionOpacity"
      to: 0; duration: Style.duration(150); easing.type: Easing.OutCubic
    }
    ScriptAction { script: root.phraseIndex = root.phraseIndex + 1 }
    PropertyAnimation {
      target: root; property: "captionOpacity"
      to: 1; duration: Style.duration(200); easing.type: Easing.OutCubic
    }
  }

  onCaptionHeldChanged: if (captionHeld) {
    captionSwap.stop()
    captionOpacity = 1
  }

  // ---- banners ----------------------------------------------------------------

  // The update banner text the user closed; a different one shows again.
  property string dismissedUpdate: ""

  // Under the mixer, most urgent first, as the other plugins' banners. The
  // engine says itself how an update ended, as one of its own notices.
  readonly property var notices: {
    var s = service
    var list = []
    if (!s) return list
    if (s.legacy) list.push({ key: "legacy", tone: "urgent", icon: Glyphs.alert,
      text: "The Sonus desktop app is still running. Routing is paused here until you switch.",
      action: "takeOver", actionLabel: "Switch" })
    if (s.noticeText !== "") list.push({ key: "engine", tone: s.noticeError ? "urgent" : "accent",
      icon: s.noticeError ? Glyphs.alert : s.noticeForm !== "" ? Glyphs.deviceGlyph(s.noticeForm) : Glyphs.info,
      text: s.noticeText, dismissable: true })
    var update = null
    if (s.update.busy && s.update.applying)
      update = { key: "update", tone: "accent", icon: Glyphs.update, text: "Updating Sonus…", busy: true }
    else if (s.updateAvailable)
      update = { key: "update", tone: "accent", icon: Glyphs.update, action: "update", actionLabel: "Update", dismissable: true,
                 text: s.update.version && s.update.version !== s.version ? "Sonus " + s.update.version + " is available" : "A Sonus update is available" }
    if (update && update.text !== dismissedUpdate) list.push(update)
    return list
  }

  function noticeAction(notice) {
    if (!service) return
    if (notice.action === "takeOver") service.takeOver()
    else if (notice.action === "update") service.applyUpdate()
  }

  function dismissNotice(notice) {
    if (notice.key === "engine" && service) service.dismissNotice()
    else if (notice.key === "update") dismissedUpdate = notice.text
  }

  // ---- views ------------------------------------------------------------------

  property string view: "mixer"

  function setView(next) {
    view = next
    menuKey = ""
    if (next === "settings" && service) service.checkUpdate(10)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function eqActive(key) {
    var st = Eq.normalized(service && service.eqs ? service.eqs[key] : null)
    return st.enabled && !Eq.isFlat(st)
  }

  function openEq(key) {
    if (key === "master" || !service) return
    var entrance = view !== "eq"
    setView("eq")
    eqView.load(key, channelTitle(key), service.eqs ? service.eqs[key] : null, entrance)
  }

  function takeRequestedView() {
    if (!service || service.requestedView === "") return
    var v = service.requestedView
    service.requestedView = ""
    if (v.indexOf("eq:") === 0) openEq(v.substring(3))
    else if (v === "settings") setView("settings")
  }

  Connections {
    target: root.service
    function onRequestedViewChanged() { if (root.opened) root.takeRequestedView() }
    function onEqsChanged() {
      if (!root.service || !root.service.reloadEq) return
      root.service.reloadEq = false
      if (root.view === "eq" && eqView.key)
        eqView.load(eqView.key, root.channelTitle(eqView.key), root.service.eqs[eqView.key], false)
    }
  }

  readonly property bool hasInput: !!(service && service.channels && service.channels.input)

  // ---- device lists -------------------------------------------------------------

  // The device in use has a tile, so the channels and apps stay in view; its
  // top line opens the list of them all, one list at a time.
  property string openDevices: ""
  // What the list shows, kept through its closing so it does not empty as it goes.
  property string shownDevices: ""
  onOpenDevicesChanged: if (openDevices !== "") shownDevices = openDevices

  function devices(section) {
    if (!service) return []
    return (section === "sink" ? service.outputs : service.inputs) || []
  }

  function devicesOpen(section) { return openDevices === section }

  function toggleDevices(section) {
    var others = devices(section).filter(function(d) { return d && d.name && !d.active })
    if (others.length === 0 && openDevices !== section) return
    openDevices = openDevices === section ? "" : section
    if (cursorActive) setCursor(section === "sink" ? "vol:out" : "vol:in")
  }

  // ---- cursor -----------------------------------------------------------------

  // One cursor for keyboard and mouse: "vol:out", "vol:in", "sink:<name>",
  // "src:<name>", "ch:<key>" or "app:<key>". The pointer moves it without
  // lighting anything, so the panel stays still under the mouse; the
  // keyboard lights it.
  property bool cursorActive: false
  property string cursorKey: ""
  property string menuKey: ""

  readonly property var cursorKeys: {
    var keys = ["vol:out"]
    // An open list's tiles come after both device tiles, in the order they
    // show, so Down follows what is on screen.
    if (service) {
      if (hasInput) keys.push("vol:in")
      if (openDevices !== "") {
        var rows = devices(openDevices)
        for (var i = 0; i < rows.length; i++) if (rows[i] && rows[i].name) keys.push(openDevices + ":" + rows[i].name)
      }
      service.appsVersion
      service.pendingRoutes
    }
    for (var c = 0; c < categories.length; c++) {
      if (service && service.channels && service.channels[categories[c].key]) keys.push("ch:" + categories[c].key)
      var inTile = service ? service.appsIn(categories[c].key) : []
      for (var j = 0; j < inTile.length; j++) keys.push("app:" + inTile[j].key)
    }
    var direct = service ? service.appsIn("") : []
    for (var d = 0; d < direct.length; d++) keys.push("app:" + direct[d].key)
    return keys
  }

  onCursorKeysChanged: {
    // The keyboard's place moves to the top. A pointer's just clears, or the
    // next `m` would mute the output with nothing lit to say so.
    if (cursorKey !== "" && cursorKeys.indexOf(cursorKey) < 0) cursorKey = cursorActive ? cursorKeys[0] : ""
    if (menuKey !== "" && cursorKeys.indexOf("app:" + menuKey) < 0) menuKey = ""
  }

  function setCursor(key) {
    cursorActive = true
    cursorKey = key
  }

  // Rows report what the pointer is over. After a key press that is ignored
  // until the pointer really moves, or a row sliding under a resting pointer
  // (a list opening, a picker) would steal the keyboard's place.
  property bool pointerMoved: false
  property point pointerAt: Qt.point(-1, -1)

  function pointAt(key) {
    if (cursorActive && !pointerMoved) return
    cursorActive = false
    cursorKey = key
  }

  function trackPointer(p) {
    if (Math.abs(p.x - pointerAt.x) + Math.abs(p.y - pointerAt.y) > 2) pointerMoved = true
    pointerAt = p
  }

  function moveCursor(delta) {
    var keys = cursorKeys
    var i = keys.indexOf(cursorKey)
    if (i < 0) i = delta > 0 ? -1 : keys.length
    cursorKey = keys[Math.max(0, Math.min(keys.length - 1, i + delta))]
  }

  function cursorTarget() {
    var parts = cursorKey.split(":")
    return parts.length > 1 ? parts.slice(1).join(":") : ""
  }

  // h/l changes a fader. A device row is a choice, so the arrows leave it alone.
  function volumeKey() {
    if (cursorKey === "vol:out") return "master"
    if (cursorKey === "vol:in") return "input"
    if (cursorKey.indexOf("ch:") === 0 || cursorKey.indexOf("app:") === 0) return cursorTarget()
    return ""
  }

  function muteKey() {
    if (cursorKey === "vol:out" || cursorKey.indexOf("sink:") === 0) return "master"
    if (cursorKey === "vol:in" || cursorKey.indexOf("src:") === 0) return "input"
    if (cursorKey.indexOf("ch:") === 0 || cursorKey.indexOf("app:") === 0) return cursorTarget()
    return ""
  }

  function selectNamed(section, name) {
    if (!service || !name) return
    var list = section === "sink" ? (service.outputs || []) : (service.inputs || [])
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].name === name) {
        selectDevice(section, list[i])
        return
      }
    }
  }

  function selectDevice(section, device) {
    if (!service || !device || !device.name || device.active) return
    if (section === "sink") service.selectOutput(device.id, device.name)
    else service.selectInput(device.id, device.name)
    openDevices = ""
    announce(Audio.switchedLine(section, device.label || ""))
    if (cursorActive) setCursor(section === "sink" ? "vol:out" : "vol:in")
  }

  function showVolumeOsd(volume) {
    if (!bar || !bar.shell || typeof bar.shell.summon !== "function") return
    bar.shell.summon("omarchy.osd", JSON.stringify({
      icon: Glyphs.outputIcon(service ? service.outputForm : "", false, volume),
      value: Math.round(volume * 100)
    }))
  }

  function ensureVisible(item) {
    if (!item || !flick) return
    var p = item.mapToItem(flick.contentItem, 0, 0)
    var margin = Style.space(6)
    if (p.y < flick.contentY + margin) flick.contentY = Math.max(0, p.y - margin)
    else if (p.y + item.height > flick.contentY + flick.height - margin)
      flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height), p.y + item.height + margin - flick.height)
  }

  // ---- volume, routing ------------------------------------------------------------

  property real wheelAcc: 0

  function wheelVolume(key, delta) {
    wheelAcc += delta
    var steps = wheelAcc > 0 ? Math.floor(wheelAcc / 120) : Math.ceil(wheelAcc / 120)
    if (steps === 0) return
    wheelAcc -= steps * 120
    service.adjustVolume(key, steps * 0.05)
  }

  function toggleMenu(key) {
    // With channels off there is nothing to pick from.
    if (routeOptions.length <= 1) return
    menuKey = menuKey === key ? "" : key
    setCursor("app:" + key)
  }

  function assign(key, channel) {
    menuKey = ""
    if (!service) return
    if (channel !== "" && !(service.channels && service.channels[channel])) return
    var info = service.appInfo[key]
    if (service.effectiveChannel(key, info ? info.channel : "") === channel) return
    service.route(key, channel)
    announce(Audio.movedLine(info ? info.name : key, channelTitle(channel)))
  }

  // ---- drag and drop ----------------------------------------------------------------

  property string dragKey: ""
  property string dropTarget: ""
  property real dragX: 0
  property real dragY: 0

  function targetAt(p) {
    var rows = [gameTile, chatTile, mediaTile, auxTile, directTile]
    var current = dragKey !== "" && service ? service.effectiveChannel(dragKey, (service.appInfo[dragKey] || {}).channel) : null
    for (var j = 0; j < rows.length; j++) {
      var r = rows[j]
      if (!r) continue
      var q = r.mapToItem(stage, 0, 0)
      var w = r.width > 0 ? r.width : r.implicitWidth
      var h = r.height > 0 ? r.height : r.implicitHeight
      if (!r.visible || !r.accepting || p.x < q.x || p.x > q.x + w || p.y < q.y || p.y > q.y + h) continue
      // Over the tile it is already in: nothing would happen, so it says so.
      return r.dropKey === (current === "" ? "master" : current) ? "" : r.dropKey
    }
    return ""
  }

  function dragMove(key, item, x, y) {
    var p = item.mapToItem(stage, x, y)
    if (dragKey !== key) {
      dragKey = key
      menuKey = ""
    }
    dragX = p.x
    dragY = p.y
    dropTarget = targetAt(p)
  }

  function dragRelease(key, item, x, y) {
    var target = targetAt(item.mapToItem(stage, x, y))
    endDrag()
    if (target === "master") assign(key, "")
    else if (target !== "") assign(key, target)
  }

  function endDrag() {
    dragKey = ""
    dropTarget = ""
  }

  // ---- lifecycle --------------------------------------------------------------

  property bool reported: false
  function report(on) {
    if (!service || on === reported) return
    reported = on
    service.openPanels = Math.max(0, service.openPanels + (on ? 1 : -1))
  }

  onOpenedChanged: {
    report(opened)
    if (opened) {
      view = "mixer"
      menuKey = ""
      openDevices = ""
      shownDevices = ""
      phraseIndex = 0
      announced = ""
      cursorActive = false
      cursorKey = ""
      endDrag()
      if (flick) flick.contentY = 0
      if (service) service.checkUpdate(60)
      takeRequestedView()
    } else {
      endDrag()
      if (service) service.persist()
    }
  }
  Component.onDestruction: report(false)

  // ---- bar button -------------------------------------------------------------

  PwObjectTracker {
    objects: Pipewire.defaultAudioSource ? [Pipewire.defaultAudioSource] : []
  }

  PwNodePeakMonitor {
    id: inputPeakMonitor
    node: Pipewire.defaultAudioSource
    enabled: root.opened && root.view === "mixer" && !!Pipewire.defaultAudioSource
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Sized like the first-party drawn icons (Tailscale, Dropbox): a little
    // inside the 16 px canvas, so its weight matches the font glyphs beside
    // it. Even sizes keep the centre on a whole pixel.
    iconComponent: Component {
      Item {
        SonusMark {
          anchors.centerIn: parent
          width: Math.round(Style.space(12) / 2) * 2
          height: width
          color: button.active && button.useActiveColor ? button.activeColor : button.foreground
          muted: !!(root.service && root.service.masterMuted)
        }
      }
    }
    tooltipText: {
      var s = root.service
      if (!s || !s.engineUp) return "Sonus"
      var lines = [(s.outputLabel || (s.master ? s.master.description : "Output")) + "  "
        + (s.masterMuted ? "muted" : Math.round(s.masterVolume * 100) + "%")]
      if (s.status) lines.push(s.status)
      if (s.updateAvailable) lines.push("Update available")
      return lines.join("\n")
    }
    onPressed: function(b) {
      if (b === Qt.MiddleButton) { if (root.service) root.service.toggleMasterMute() }
      else if (b === Qt.RightButton) {
        if (root.opened && root.view === "settings") root.close()
        else {
          if (!root.opened) root.open()
          root.setView("settings")
        }
      } else root.toggle()
    }
    onWheelMoved: function(delta) {
      if (!root.service) return
      root.wheelVolume("master", delta)
      root.showVolumeOsd(root.service.volumeOf("master"))
    }
  }

  // ---- panel --------------------------------------------------------------------

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    // Settings is a short list and keeps Omarchy's own width. The equalizer
    // stays wide so opening it from a tile leaves the pointer in the panel.
    contentWidth: panel.fittedContentWidth(root.view === "settings" ? Style.space(380) : root.mixerWidth)
    contentHeight: panel.fittedContentHeight(
      root.view === "eq" ? eqView.implicitHeight
        : root.view === "settings" ? settingsView.implicitHeight : mixerColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        root.pointerMoved = false
        if (root.view === "eq") { eqView.handleMove(dx, dy); return }
        if (root.view !== "mixer") return
        if (!root.cursorActive) {
          root.setCursor(root.cursorKey !== "" ? root.cursorKey : "vol:out")
          return
        }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0 && root.service && root.volumeKey()) root.service.adjustVolume(root.volumeKey(), dx * 0.05)
        // A device list is laid out sideways, so sideways keys walk it too.
        else if (dx !== 0 && root.cursorKey.indexOf(":") > 0 && root.openDevices !== "" && root.cursorKey.indexOf(root.openDevices + ":") === 0) root.moveCursor(dx)
      }
      onActivateRequested: {
        root.pointerMoved = false
        if (root.view !== "mixer" || !root.cursorActive || !root.service) return
        var key = root.cursorKey
        if (key.indexOf("sink:") === 0) root.selectNamed("sink", root.cursorTarget())
        else if (key.indexOf("src:") === 0) root.selectNamed("src", root.cursorTarget())
        else if (key === "vol:out") root.toggleDevices("sink")
        else if (key === "vol:in") root.toggleDevices("src")
        else if (key.indexOf("app:") === 0) root.toggleMenu(root.cursorTarget())
        else if (key.indexOf("ch:") === 0) root.openEq(root.cursorTarget())
      }
      onCloseRequested: {
        if (root.dragKey !== "") root.endDrag()
        else if (root.menuKey !== "") root.menuKey = ""
        else if (root.openDevices !== "") {
          var opener = root.openDevices === "sink" ? "vol:out" : "vol:in"
          root.openDevices = ""
          if (root.cursorActive) root.setCursor(opener)
        }
        else if (root.view !== "mixer") root.setView("mixer")
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        root.pointerMoved = false
        if (root.view === "eq") {
          if (t === "e") root.setView("mixer")
          else eqView.handleText(t.toLowerCase())
          return
        }
        var key = t.toLowerCase()
        var target = root.cursorTarget()
        if (key === "s" || key === ",") root.setView(root.view === "settings" ? "mixer" : "settings")
        else if (root.view !== "mixer") return
        else if (key === "m" && root.service && root.muteKey()) root.service.setMute(root.muteKey(), !root.service.mutedOf(root.muteKey()))
        else if (key === "e" && root.cursorKey.indexOf("ch:") === 0) root.openEq(target)
        else if ("01234".indexOf(key) >= 0) {
          // The app whose picker is open, not whichever the pointer has reached.
          var appKey = root.menuKey !== "" ? root.menuKey : root.cursorKey.indexOf("app:") === 0 ? target : ""
          if (appKey !== "") root.assign(appKey, key === "0" ? "" : root.categories[Number(key) - 1].key)
        }
      }

      Item {
        id: stage
        anchors.fill: parent

        HoverHandler {
          onPointChanged: root.trackPointer(point.scenePosition)
          // Off the panel, the pointer aims at nothing, and `m` should not act.
          onHoveredChanged: if (!hovered && !root.cursorActive && root.dragKey === "") root.cursorKey = ""
        }

        // ---- mixer ----------------------------------------------------------
        Flickable {
          id: flick
          anchors.fill: parent
          visible: root.view === "mixer"
          contentWidth: width
          contentHeight: mixerColumn.implicitHeight
          clip: true
          interactive: contentHeight > height && root.dragKey === ""
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: mixerColumn
            width: flick.width
            spacing: root.tileGap

            Column {
              width: parent.width

              // The top row: the title in the first column, over Game, and the
              // output and input filling the rest. No empty header above them.
              Row {
                id: topRow
                readonly property real deviceWidth: root.hasInput
                  ? (width - channelRow.tileWidth - root.tileGap * 2) / 2
                  : width - channelRow.tileWidth - root.tileGap
                readonly property real rowHeight: Math.max(topHero.implicitHeight, outputTile.implicitHeight,
                  inputTile.visible ? inputTile.implicitHeight : 0)
                width: parent.width
                spacing: root.tileGap

                HeroBlock {
                  id: topHero
                  width: channelRow.tileWidth
                  height: topRow.rowHeight
                  host: root
                  title: "Sonus"
                  line: root.heroLine
                  lineOpacity: root.captionOpacity
                  iconComponent: Component {
                    Item {
                      SonusMark {
                        anchors.centerIn: parent
                        width: Math.round(Style.font.display / 2) * 2
                        height: width
                        color: root.fg
                        muted: !!(root.service && root.service.masterMuted)
                      }
                    }
                  }

                  PanelActionButton {
                    iconText: Glyphs.cog
                    tooltipText: "Settings (s)"
                    foreground: root.fg
                    fontFamily: root.fontFamily
                    onClicked: root.setView("settings")
                  }
                }

                DeviceTile {
                  id: outputTile
                  width: topRow.deviceWidth
                  height: topRow.rowHeight
                  host: root
                  section: "sink"
                  key: "master"
                  cursor: "vol:out"
                  role: "Output"
                }

                DeviceTile {
                  id: inputTile
                  visible: root.hasInput
                  width: topRow.deviceWidth
                  height: topRow.rowHeight
                  host: root
                  section: "src"
                  key: "input"
                  cursor: "vol:in"
                  role: "Input"
                  mic: true
                  metered: true
                  peak: inputPeakMonitor.peak
                }
              }

              // Slides open between the devices and the channels, so the tiles
              // below are pushed gently instead of jumping. Its gap above is part
              // of its height, so closing ends without a snap.
              Item {
                id: deviceDrawer
                readonly property bool isOpen: root.openDevices !== ""
                clip: true
                width: parent.width
                height: isOpen ? deviceList.implicitHeight + root.tileGap : 0
                opacity: isOpen ? 1 : 0

                Behavior on height {
                  NumberAnimation {
                    duration: Style.duration(deviceDrawer.isOpen ? 180 : 120)
                    easing.type: Easing.OutCubic
                  }
                }
                Behavior on opacity {
                  NumberAnimation {
                    duration: Style.duration(deviceDrawer.isOpen ? 180 : 120)
                    easing.type: Easing.OutCubic
                  }
                }

                DeviceList {
                  id: deviceList
                  y: root.tileGap
                  width: parent.width
                  host: root
                  section: root.shownDevices
                }
              }
            }

            // One row, every tile as tall as the tallest, so the buckets line
            // up along the bottom and a drop never has far to go.
            Row {
              id: channelRow
              readonly property real tileWidth: (width - root.tileGap * 3) / 4
              readonly property real tileHeight: Math.max(gameTile.implicitHeight, chatTile.implicitHeight,
                mediaTile.implicitHeight, auxTile.implicitHeight)
              width: parent.width
              spacing: root.tileGap

              ChannelTile { id: gameTile; width: channelRow.tileWidth; height: channelRow.tileHeight; host: root; key: "game"; title: "Game" }
              ChannelTile { id: chatTile; width: channelRow.tileWidth; height: channelRow.tileHeight; host: root; key: "chat"; title: "Chat" }
              ChannelTile { id: mediaTile; width: channelRow.tileWidth; height: channelRow.tileHeight; host: root; key: "media"; title: "Media" }
              ChannelTile { id: auxTile; width: channelRow.tileWidth; height: channelRow.tileHeight; host: root; key: "aux"; title: "Aux" }
            }

            NoChannelTile {
              id: directTile
              visible: apps.length > 0 || root.dragKey !== ""
              width: parent.width
              height: implicitHeight
              host: root
              labelWidth: channelRow.tileWidth
            }

            // What the engine has to say (a restored device mix, a failed
            // write), the desktop app in the way, an update: the panel kit's
            // banners, under the tiles so a banner coming or going never moves
            // a fader out from under the pointer.
            Repeater {
              model: root.notices

              Notice {
                required property var modelData
                width: mixerColumn.width
                icon: modelData.icon
                text: modelData.text
                tone: modelData.tone
                actionLabel: modelData.actionLabel || ""
                busy: !!modelData.busy
                dismissable: !!modelData.dismissable
                foreground: root.fg
                fontFamily: root.fontFamily
                onActioned: root.noticeAction(modelData)
                onDismissed: root.dismissNotice(modelData)
              }
            }
          }
        }

        // ---- EQ and settings --------------------------------------------------
        EqView {
          id: eqView
          host: root
          width: parent.width
          visible: root.view === "eq"
        }

        SettingsView {
          id: settingsView
          host: root
          width: parent.width
          visible: root.view === "settings"
        }

        // The card in the air, following the pointer: the same grip, icon
        // and name as in its tile, and where it will land.
        BorderSurface {
          visible: root.dragKey !== ""
          x: Math.max(0, Math.min(root.dragX - Style.space(14), stage.width - width))
          y: root.dragY - height / 2
          width: ghostRow.implicitWidth + Style.space(20)
          height: Style.space(28)
          radius: Style.cornerRadius
          color: Commons.Color.popups.background
          borderSpec: Border.controlSpec(root.dropTarget !== "" ? "selected" : "hover-cursor", root.fg, Commons.Color.accent)

          Row {
            id: ghostRow
            x: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Grip {
              anchors.verticalCenter: parent.verticalCenter
              color: root.fg
            }

            Image {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(16)
              height: width
              visible: status === Image.Ready
              source: root.dragKey !== "" && root.service ? (root.service.iconCache[root.dragKey] || "") : ""
              sourceSize.width: width * 2
              sourceSize.height: height * 2
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.dragName
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Text {
              visible: root.dropTarget !== ""
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "to " + root.channelTitle(root.dropTarget === "master" ? "" : root.dropTarget)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }
}
