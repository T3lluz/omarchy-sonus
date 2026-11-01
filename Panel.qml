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
// then the four channels as lanes holding the apps that play into them.
// Dragging an app's chip to another lane moves it there. Picking an output
// also brings back that device's volume and equalizer. All state lives in
// the service; this only draws it.
Panel {
  id: root
  moduleName: "io.github.t3lluz.sonus"
  manageIpc: false

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null

  readonly property color fg: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(fg, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // One grid for every row: icon, name, fader, level. The device, channel
  // and app faders all start and end at the same x, and every level lines
  // up on the right, so the panel reads down its columns. An app's chip
  // starts under its channel's name, inside the channel.
  readonly property real rowPad: Style.space(8)
  readonly property real iconW: Style.space(24)
  readonly property real iconH: Style.space(18)
  readonly property real nameX: rowPad + iconW + Style.space(10)
  readonly property real nameW: Style.space(136)
  readonly property real faderX: nameX + nameW + Style.space(10)
  readonly property real readingW: Style.space(46)
  readonly property real readingSize: Style.font.heading
  readonly property real chipX: nameX - Style.space(6)
  readonly property real chipWidth: faderX - Style.space(10) - chipX
  readonly property real chipH: Style.space(28)

  function faderWidth(rowWidth) { return rowWidth - rowPad - readingW - Style.space(10) - faderX }

  readonly property int appCount: service ? service.appsModel.count : 0

  readonly property var categories: [
    { key: "game", title: "Game" },
    { key: "chat", title: "Chat" },
    { key: "media", title: "Media" },
    { key: "aux", title: "Aux" }
  ]
  readonly property var routeOptions: [
    { value: "game", label: "Game" },
    { value: "chat", label: "Chat" },
    { value: "media", label: "Media" },
    { value: "aux", label: "Aux" },
    { value: "", label: "No channel" }
  ]

  function channelTitle(key) {
    for (var i = 0; i < categories.length; i++) if (categories[i].key === key) return categories[i].title
    return "No channel"
  }

  // ---- banners ----------------------------------------------------------------

  // The update banner text the user closed; a different one shows again.
  property string dismissedUpdate: ""

  // Over the mixer, most urgent first, as the other plugins' banners. The
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

  // The device in use stands alone, so the channels and apps stay in view.
  // Its name opens the others.
  property bool outputsOpen: false
  property bool inputsOpen: false

  function devices(section) {
    if (!service) return []
    return (section === "sink" ? service.outputs : service.inputs) || []
  }

  function devicesOpen(section) { return section === "sink" ? outputsOpen : inputsOpen }

  function setDevicesOpen(section, open) {
    if (section === "sink") outputsOpen = open
    else inputsOpen = open
  }

  function toggleDevices(section) {
    setDevicesOpen(section, !devicesOpen(section))
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
    if (service) {
      var outs = outputsOpen ? (service.outputs || []) : []
      for (var i = 0; i < outs.length; i++) if (outs[i] && outs[i].name && !outs[i].active) keys.push("sink:" + outs[i].name)
      if (hasInput) {
        keys.push("vol:in")
        var ins = inputsOpen ? (service.inputs || []) : []
        for (var n = 0; n < ins.length; n++) if (ins[n] && ins[n].name && !ins[n].active) keys.push("src:" + ins[n].name)
      }
      service.appsVersion
      service.pendingRoutes
    }
    for (var c = 0; c < categories.length; c++) {
      keys.push("ch:" + categories[c].key)
      var inLane = service ? service.appsIn(categories[c].key) : []
      for (var j = 0; j < inLane.length; j++) keys.push("app:" + inLane[j].key)
    }
    var direct = service ? service.appsIn("") : []
    for (var d = 0; d < direct.length; d++) keys.push("app:" + direct[d].key)
    return keys
  }

  onCursorKeysChanged: {
    if (cursorKey !== "" && cursorKeys.indexOf(cursorKey) < 0) cursorKey = cursorKeys[0]
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
    setDevicesOpen(section, false)
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
    menuKey = menuKey === key ? "" : key
    setCursor("app:" + key)
  }

  function assign(key, channel) {
    menuKey = ""
    if (!service) return
    var info = service.appInfo[key]
    if (service.effectiveChannel(key, info ? info.channel : "") !== channel) service.route(key, channel)
  }

  // ---- drag and drop ----------------------------------------------------------------

  property string dragKey: ""
  property string dropTarget: ""
  property real dragX: 0
  property real dragY: 0

  function targetAt(p) {
    var rows = [gameLane, chatLane, mediaLane, auxLane, directLane]
    for (var j = 0; j < rows.length; j++) {
      var r = rows[j]
      if (!r) continue
      var q = r.mapToItem(stage, 0, 0)
      var w = r.width > 0 ? r.width : r.implicitWidth
      var h = r.height > 0 ? r.height : r.implicitHeight
      if (r.visible && p.x >= q.x && p.x <= q.x + w && p.y >= q.y && p.y <= q.y + h) return r.dropKey
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
      outputsOpen = false
      inputsOpen = false
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
    contentWidth: panel.fittedContentWidth(Style.space(root.view === "eq" ? 460 : 420))
    contentHeight: panel.fittedContentHeight(
      root.view === "eq" ? eqView.implicitHeight
        : root.view === "settings" ? settingsView.implicitHeight : mixerColumn.implicitHeight,
      Style.space(780))

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
        if (root.menuKey !== "") root.menuKey = ""
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
        var target = root.cursorActive ? root.cursorTarget() : ""
        if (key === "s" || key === ",") root.setView(root.view === "settings" ? "mixer" : "settings")
        else if (root.view !== "mixer") return
        else if (key === "m" && root.service && root.muteKey()) root.service.setMute(root.muteKey(), !root.service.mutedOf(root.muteKey()))
        else if (key === "e" && root.cursorKey.indexOf("ch:") === 0) root.openEq(target)
        else if (root.cursorKey.indexOf("app:") === 0 && "01234".indexOf(key) >= 0) {
          root.assign(target, key === "0" ? "" : root.categories[Number(key) - 1].key)
        }
      }

      Item {
        id: stage
        anchors.fill: parent

        HoverHandler {
          onPointChanged: root.trackPointer(point.scenePosition)
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
            spacing: Style.space(14)

            PanelHero {
              width: parent.width
              title: "Sonus"
              meta: {
                var s = root.service
                if (!s || !s.engineUp) return "Starting"
                return Audio.appsLine(root.appCount) + " · " + Audio.volumeName(outputGroup.level, s.masterMuted)
              }
              foreground: root.fg
              fontFamily: root.fontFamily
              iconComponent: Component {
                Item {
                  implicitWidth: Style.font.display
                  implicitHeight: Style.font.display

                  SonusMark {
                    anchors.centerIn: parent
                    width: Math.round(Style.font.display / 2) * 2
                    height: width
                    color: root.fg
                    muted: !!(root.service && root.service.masterMuted)
                  }
                }
              }
              trailingControl: Component {
                PanelActionButton {
                  iconText: Glyphs.cog
                  tooltipText: "Settings (s)"
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  onClicked: root.setView("settings")
                }
              }
            }

            // What the engine has to say (a restored device mix, a failed
            // write), the desktop app in the way, an update: the panel kit's
            // banners, as in the other plugins.
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

            Column {
              width: parent.width

              DeviceGroup {
                id: outputGroup
                host: root
                section: "sink"
                key: "master"
                cursor: "vol:out"
                role: "Output"
              }

              DeviceGroup {
                id: inputGroup
                visible: root.hasInput
                host: root
                section: "src"
                key: "input"
                cursor: "vol:in"
                role: "Input"
                metered: true
                peak: inputPeakMonitor.peak
              }
            }

            PanelSeparator { foreground: root.fg }

            // Named the way Batteries names a group: bold on the left, what
            // to do with it dim on the right.
            Item {
              readonly property bool channelsOn: !!(root.service && root.service.channels && root.service.channels.game)
              width: parent.width
              height: Math.max(channelsName.implicitHeight, channelsHint.implicitHeight)

              Text {
                id: channelsName
                x: root.rowPad
                textFormat: Text.PlainText
                text: "Channels"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }

              Text {
                id: channelsHint
                anchors.right: parent.right
                anchors.rightMargin: root.rowPad
                anchors.baseline: channelsName.baseline
                width: parent.width - channelsName.implicitWidth - root.rowPad * 2 - Style.space(16)
                horizontalAlignment: Text.AlignRight
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: !parent.channelsOn ? "Switched off in settings"
                  : root.dragKey !== "" ? "Drop it on a channel"
                  : root.appCount > 0 ? "Drag apps between channels"
                  : "Apps show up here while they play"
                color: root.dragKey !== "" ? root.fg : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              ChannelLane { id: gameLane; host: root; key: "game"; title: "Game" }
              PanelSeparator { foreground: root.fg; strength: 0.06 }
              ChannelLane { id: chatLane; host: root; key: "chat"; title: "Chat" }
              PanelSeparator { foreground: root.fg; strength: 0.06 }
              ChannelLane { id: mediaLane; host: root; key: "media"; title: "Media" }
              PanelSeparator { foreground: root.fg; strength: 0.06 }
              ChannelLane { id: auxLane; host: root; key: "aux"; title: "Aux" }
              PanelSeparator { visible: directLane.visible; foreground: root.fg; strength: 0.06 }

              // Apps that skip the channels; while dragging, the way to send
              // one there.
              ChannelLane {
                id: directLane
                visible: apps.length > 0 || root.dragKey !== ""
                host: root
                title: "No channel"
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

        // The chip in the air, following the pointer: the same grip, icon
        // and name as in its lane, and where it will land.
        BorderSurface {
          visible: root.dragKey !== ""
          x: Math.max(0, Math.min(root.dragX - Style.space(14), stage.width - width))
          y: root.dragY - height / 2
          width: ghostRow.implicitWidth + Style.space(20)
          height: root.chipH
          radius: Style.cornerRadius
          color: Commons.Color.popups.background
          borderSpec: Border.controlSpec(root.dropTarget !== "" ? "selected" : "hover-cursor", root.fg, Commons.Color.accent)

          Row {
            id: ghostRow
            x: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Grid {
              anchors.verticalCenter: parent.verticalCenter
              columns: 2
              spacing: Style.space(2)

              Repeater {
                model: 6
                Rectangle {
                  width: Math.max(2, Style.space(2))
                  height: width
                  radius: width / 2
                  color: root.fg
                }
              }
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
              text: {
                if (root.dragKey === "" || !root.service) return ""
                var info = root.service.appInfo[root.dragKey]
                return info ? info.name : root.dragKey
              }
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
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }
    }
  }
}
