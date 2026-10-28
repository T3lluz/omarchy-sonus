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

// Sonus in the bar. The mark drops the panel: system output and input, the
// four channels (each with its EQ) and every app playing sound. Picking an
// output also brings back that device's volume and equalizer. All state
// lives in the service; this only draws it.
Panel {
  id: root
  moduleName: "io.github.t3lluz.sonus"
  manageIpc: false

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null

  readonly property color fg: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: Style.hoverFillFor(fg, Commons.Color.accent)
  readonly property color selectedFill: Style.selectedFillFor(fg, Commons.Color.accent)

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
    { value: "", label: "Output" }
  ]

  function channelTitle(key) {
    for (var i = 0; i < categories.length; i++) if (categories[i].key === key) return categories[i].title
    return "Output"
  }

  function levelText(level) {
    return level.muted ? "muted" : Math.round(level.shownVolume * 100) + "%"
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

  // Collapsed, a device list shows only the device in use, so the channels
  // and apps stay in view. Clicking that row opens the rest.
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

  function deviceShown(section, device) {
    if (!device || device.active || devicesOpen(section)) return true
    var list = devices(section)
    for (var i = 0; i < list.length; i++) if (list[i] && list[i].active) return false
    return true
  }

  // ---- cursor -----------------------------------------------------------------

  // One cursor for keyboard and mouse: "vol:out", "vol:in", "sink:<name>",
  // "src:<name>", "ch:<key>" or "app:<key>".
  property bool cursorActive: false
  property string cursorKey: ""
  property string menuKey: ""

  readonly property var cursorKeys: {
    var keys = ["vol:out"]
    if (service) {
      var outs = service.outputs || []
      for (var i = 0; i < outs.length; i++) if (outs[i] && outs[i].name && deviceShown("sink", outs[i])) keys.push("sink:" + outs[i].name)
      if (service.channels && service.channels.input) {
        keys.push("vol:in")
        var ins = service.inputs || []
        for (var n = 0; n < ins.length; n++) if (ins[n] && ins[n].name && deviceShown("src", ins[n])) keys.push("src:" + ins[n].name)
      }
      service.appsVersion
    }
    for (var c = 0; c < categories.length; c++) keys.push("ch:" + categories[c].key)
    if (service) {
      for (var j = 0; j < service.appsModel.count; j++) keys.push("app:" + service.appsModel.get(j).key)
    }
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

  // The device in use opens and closes its list; any other is picked.
  function selectDevice(section, device) {
    if (!service || !device || !device.name) return
    setCursor(section + ":" + device.name)
    if (device.active) {
      if (devices(section).length > 1) setDevicesOpen(section, !devicesOpen(section))
      return
    }
    if (section === "sink") service.selectOutput(device.id, device.name)
    else service.selectInput(device.id, device.name)
    setDevicesOpen(section, false)
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
    var rows = [outputSection, gameRow, chatRow, mediaRow, auxRow]
    for (var j = 0; j < rows.length; j++) {
      var r = rows[j]
      if (!r) continue
      var q = r.mapToItem(stage, 0, 0)
      var w = r.width > 0 ? r.width : r.implicitWidth
      var h = r.height > 0 ? r.height : r.implicitHeight
      if (p.x >= q.x && p.x <= q.x + w && p.y >= q.y && p.y <= q.y + h) return r.key
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
      Style.space(660))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
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
        if (root.view !== "mixer" || !root.cursorActive || !root.service) return
        var key = root.cursorKey
        if (key.indexOf("sink:") === 0) root.selectNamed("sink", root.cursorTarget())
        else if (key.indexOf("src:") === 0) root.selectNamed("src", root.cursorTarget())
        else if (key === "vol:out") root.service.setMute("master", !root.service.mutedOf("master"))
        else if (key === "vol:in") root.service.setMute("input", !root.service.mutedOf("input"))
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

            Item {
              width: parent.width
              implicitHeight: Math.max(heroMark.height, heroText.implicitHeight, settingsButton.implicitHeight)

              SonusMark {
                id: heroMark
                width: Style.font.display
                height: width
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                color: root.fg
                muted: !!(root.service && root.service.masterMuted)
              }

              Column {
                id: heroText
                anchors.left: heroMark.right
                anchors.leftMargin: Style.space(14)
                anchors.right: settingsButton.left
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: "Sonus"
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: {
                    var s = root.service
                    if (!s || !s.engineUp) return "STARTING"
                    var name = s.outputLabel || (s.master ? s.master.description : "Output")
                    return (name + "  ·  " + Audio.volumeName(outputLevel.shownVolume, s.masterMuted)).toUpperCase()
                  }
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.2
                  elide: Text.ElideRight
                }
              }

              PanelActionButton {
                id: settingsButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: Glyphs.cog
                tooltipText: root.service && root.service.updateAvailable ? "Settings (s) · update available" : "Settings (s)"
                foreground: root.fg
                fontFamily: root.fontFamily
                onClicked: root.setView("settings")

                // An update is waiting.
                Rectangle {
                  visible: !!root.service && root.service.updateAvailable
                  width: Style.space(7)
                  height: width
                  radius: width / 2
                  color: Commons.Color.accent
                  anchors.top: parent.top
                  anchors.right: parent.right
                }
              }
            }

            // What the engine has to say: a restored device mix, a failed
            // write, an update. Click to dismiss; it also goes by itself.
            CursorSurface {
              visible: !!root.service && root.service.noticeText !== ""
              width: parent.width
              implicitHeight: noticeRow.implicitHeight + Style.spacing.lg
              current: true
              foreground: root.fg
              currentFill: root.service && root.service.noticeError
                ? Style.selectedFillFor(Commons.Color.urgent, Commons.Color.urgent)
                : root.selectedFill

              Row {
                id: noticeRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(8)

                Text {
                  id: noticeGlyph
                  width: Style.space(22)
                  horizontalAlignment: Text.AlignHCenter
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: root.service && root.service.noticeError ? Glyphs.alert : Glyphs.info
                  color: root.service && root.service.noticeError ? Commons.Color.urgent : root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                Text {
                  width: parent.width - noticeGlyph.width - parent.spacing
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  wrapMode: Text.WordWrap
                  text: root.service ? root.service.noticeText : ""
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.service.dismissNotice()
              }
            }

            // The desktop app would fight this panel over routes.
            CursorSurface {
              visible: !!root.service && root.service.legacy
              width: parent.width
              implicitHeight: legacyRow.implicitHeight + Style.spacing.xl
              current: true
              foreground: root.fg
              currentFill: Style.selectedFillFor(Commons.Color.urgent, Commons.Color.urgent)

              Item {
                id: legacyRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                implicitHeight: Math.max(legacyText.implicitHeight, switchButton.implicitHeight)

                Text {
                  id: legacyText
                  anchors.left: parent.left
                  anchors.right: switchButton.left
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  wrapMode: Text.WordWrap
                  text: "The Sonus desktop app is still running. Routing is paused here until you switch."
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Button {
                  id: switchButton
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Switch"
                  tooltipText: "Stop the desktop app and its autostart; Sonus runs here from now on"
                  bordered: true
                  selected: true
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  onClicked: root.service.takeOver()
                }
              }
            }

            // Also the drop target that takes an app back to the plain output.
            Section {
              id: outputSection
              width: parent.width
              key: "master"
              title: "OUTPUT"
              meta: root.levelText(outputLevel)
              hot: root.dragKey !== "" && root.dropTarget === "master"
              foreground: root.fg
              fontFamily: root.fontFamily

              LevelRow {
                id: outputLevel
                host: root
                key: "master"
                cursor: "vol:out"
                glyph: Glyphs.outputIcon(root.service ? root.service.outputForm : "", muted, shownVolume)
              }

              Repeater {
                model: root.service ? root.service.outputs : []
                DeviceRow {
                  width: parent.width
                  host: root
                  section: "sink"
                }
              }

              Text {
                visible: !root.service || !root.service.outputs || root.service.outputs.length === 0
                leftPadding: Style.space(6)
                text: "No output devices"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Section {
              width: parent.width
              visible: root.hasInput || (!!root.service && !!root.service.inputs && root.service.inputs.length > 0)
              title: "INPUT"
              meta: root.hasInput ? root.levelText(inputLevel) : ""
              foreground: root.fg
              fontFamily: root.fontFamily

              LevelRow {
                id: inputLevel
                visible: root.hasInput
                host: root
                key: "input"
                cursor: "vol:in"
                glyph: muted ? Glyphs.microphoneOff : Glyphs.microphone
                metered: true
                peak: inputPeakMonitor.peak
              }

              Repeater {
                model: root.service ? root.service.inputs : []
                DeviceRow {
                  width: parent.width
                  host: root
                  section: "src"
                }
              }
            }

            Section {
              width: parent.width
              title: "CHANNELS"
              foreground: root.fg
              fontFamily: root.fontFamily

              Grid {
                id: channelGrid
                width: parent.width
                columns: 2
                spacing: Style.space(8)

                readonly property real cell: (width - spacing) / 2

                ChannelRow { id: gameRow; host: root; key: "game"; title: "Game"; width: channelGrid.cell }
                ChannelRow { id: chatRow; host: root; key: "chat"; title: "Chat"; width: channelGrid.cell }
                ChannelRow { id: mediaRow; host: root; key: "media"; title: "Media"; width: channelGrid.cell }
                ChannelRow { id: auxRow; host: root; key: "aux"; title: "Aux"; width: channelGrid.cell }
              }
            }

            Section {
              width: parent.width
              title: "APPS"
              meta: root.service && root.service.appsModel.count > 0 ? "drag onto a channel" : ""
              foreground: root.fg
              fontFamily: root.fontFamily

              Text {
                visible: !root.service || root.service.appsModel.count === 0
                leftPadding: Style.space(6)
                text: "Apps show up here while they play."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Repeater {
                model: root.service ? root.service.appsModel : null

                AppRow {
                  host: root
                  width: parent.width
                }
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

        // Chip following the pointer while an app is dragged.
        Rectangle {
          visible: root.dragKey !== ""
          x: Math.min(root.dragX + Style.space(12), stage.width - width)
          y: root.dragY - height / 2
          width: ghostRow.implicitWidth + Style.space(18)
          height: Style.space(28)
          radius: Style.cornerRadius > 0 ? height / 2 : 0
          color: Commons.Color.popups.background
          border.width: Math.max(1, Style.space(1))
          border.color: root.dropTarget !== "" ? Commons.Color.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.3)

          Row {
            id: ghostRow
            anchors.centerIn: parent
            spacing: Style.space(6)

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
              text: {
                if (root.dragKey === "" || !root.service) return ""
                var info = root.service.appInfo[root.dragKey]
                var name = info ? info.name : root.dragKey
                if (root.dropTarget === "master") return name + "  →  Output"
                if (root.dropTarget !== "") return name + "  →  " + root.channelTitle(root.dropTarget)
                return name
              }
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }
        }
      }
    }
  }
}
