import QtQuick
import Quickshell
import Quickshell.Io
import "ui/Eq.js" as Eq

// The plugin's always-on half. It runs the engine (bin/sonus-engine), which
// owns the virtual channels and keeps every app routed whether the mixer is
// open or not, mirrors the engine's state for the window and the bar, and
// answers `omarchy-shell sonus toggle` for the hotkey.
//
// The window lives here rather than in the bar widget so it is not the
// bar's: with the button taken out of the bar, routing, the hotkey and the
// window all keep working.
Scope {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  readonly property string pluginId: "io.github.t3lluz.sonus"
  readonly property string version: manifest && manifest.version ? String(manifest.version) : "1.0.0"

  // From this file's URL rather than the manifest: the shell strips
  // __sourceDir from third-party manifests.
  readonly property string sourceDir: {
    var url = String(Qt.resolvedUrl("."))
    if (url.indexOf("file://") !== 0) return ""
    try { url = decodeURIComponent(url.substring(7)) } catch (e) { return "" }
    return url.replace(/\/$/, "")
  }

  // ---- engine state ---------------------------------------------------------

  property bool engineUp: false
  property bool configLoaded: false
  property var channels: ({})
  property ListModel appsModel: ListModel {}
  property var appInfo: ({})
  property int appsVersion: 0
  property string mixTarget: ""
  property bool ready: false
  property bool legacy: false
  property bool effectsRunning: false
  property string status: ""
  property var routes: ({})
  property var eqs: ({})
  property bool manageGraph: true
  property var savedPos: null
  property string noticeText: ""
  property bool noticeError: false
  property var update: ({ state: "unknown", local: "", busy: false, applying: false })
  property double lastUpdateCheck: 0
  // Optimistic assignments, shown until a snapshot confirms them.
  property var pendingRoutes: ({})

  readonly property var master: channels.master || null
  readonly property real masterVolume: master ? master.volume : 0
  readonly property bool masterMuted: master ? master.muted : false

  function send(message) {
    if (engine.running) engine.write(JSON.stringify(message) + "\n")
  }

  // ---- icons ------------------------------------------------------------------

  property var iconCache: ({})

  function resolveIcon(app) {
    var names = [app.icon_name, app.binary, String(app.name || "").toLowerCase(),
      String(app.name || "").toLowerCase().replace(/\s+/g, "-")]
    for (var i = 0; i < names.length; i++) {
      if (!names[i]) continue
      var path = Quickshell.iconPath(names[i], true)
      if (path) return path
    }
    // Electron apps often report a binary ("zen-bin") no icon theme knows;
    // their desktop entry does.
    for (var j = 0; j < names.length; j++) {
      if (!names[j]) continue
      try {
        var entry = DesktopEntries.heuristicLookup(names[j])
        if (entry && entry.icon) {
          var found = Quickshell.iconPath(entry.icon, true)
          if (found) return found
        }
      } catch (e) {}
    }
    return Quickshell.iconPath("audio-x-generic", true) || ""
  }

  function iconFor(app) {
    if (iconCache[app.key] !== undefined) return iconCache[app.key]
    var path = resolveIcon(app)
    iconCache[app.key] = path
    return path
  }

  // ---- snapshots ----------------------------------------------------------------

  function indexOfApp(key) {
    for (var i = 0; i < appsModel.count; i++) if (appsModel.get(i).key === key) return i
    return -1
  }

  // Updates the model in place so strips keep their identity: a strip being
  // dragged or animated must not be rebuilt under the pointer.
  function syncApps(list) {
    var info = {}
    for (var i = 0; i < list.length; i++) info[list[i].key] = list[i]
    for (var r = appsModel.count - 1; r >= 0; r--)
      if (!info[appsModel.get(r).key]) appsModel.remove(r)
    for (var j = 0; j < list.length; j++) {
      var a = list[j]
      var row = {
        key: a.key, name: a.name, binary: a.binary, volume: a.volume,
        muted: a.muted, channel: a.channel, icon: iconFor(a)
      }
      var idx = indexOfApp(a.key)
      if (idx < 0) {
        appsModel.insert(j, row)
        continue
      }
      if (idx !== j) appsModel.move(idx, j, 1)
      var cur = appsModel.get(j)
      for (var field in row) if (cur[field] !== row[field]) appsModel.setProperty(j, field, row[field])
    }
    appInfo = info
    appsVersion++
  }

  function prunePending() {
    var now = Date.now()
    var next = {}
    var changed = false
    for (var key in pendingRoutes) {
      var p = pendingRoutes[key]
      var app = appInfo[key]
      if (!app || app.channel === p.channel || now - p.at > 6000) changed = true
      else next[key] = p
    }
    if (changed) pendingRoutes = next
  }

  function effectiveChannel(key, snapChannel) {
    var p = pendingRoutes[key]
    return p ? p.channel : (snapChannel || "")
  }

  function handleLine(line) {
    var msg
    try { msg = JSON.parse(line) } catch (e) { return }
    if (!msg || typeof msg !== "object") return
    if (msg.type === "state") {
      channels = msg.channels || {}
      syncApps(msg.apps || [])
      prunePending()
      mixTarget = msg.mixTarget || ""
      ready = msg.ready === true
      legacy = msg.legacy === true
      effectsRunning = msg.effectsRunning === true
      status = msg.status || ""
      engineUp = true
    } else if (msg.type === "config") {
      routes = msg.routes || {}
      var next = {}
      var stored = msg.eq || {}
      for (var k in stored) next[k] = Eq.normalized(stored[k])
      eqs = next
      manageGraph = msg.manageGraph !== false
      savedPos = msg.pos && typeof msg.pos === "object" ? msg.pos : null
      configLoaded = true
    } else if (msg.type === "update") {
      var u = {}
      for (var a in update) u[a] = update[a]
      for (var b in msg) if (b !== "type") u[b] = msg[b]
      if (msg.busy === false) u.applying = false
      update = u
    } else if (msg.type === "notice") {
      noticeText = msg.text || ""
      noticeError = msg.error === true
      noticeTimer.restart()
    }
  }

  Timer {
    id: noticeTimer
    interval: 6000
    onTriggered: root.noticeText = ""
  }

  // ---- commands ---------------------------------------------------------------

  function idsFor(key) {
    if (channels[key]) return [channels[key].node_id]
    var app = appInfo[key]
    return app ? (app.members && app.members.length ? app.members : [app.node_id]) : []
  }

  function setVolume(key, value) {
    var ids = idsFor(key)
    if (ids.length) send({ cmd: "volume", ids: ids, value: Math.max(0, Math.min(1, value)) })
  }

  function setMute(key, value) {
    var ids = idsFor(key)
    if (ids.length) send({ cmd: "mute", ids: ids, value: !!value })
  }

  function route(key, channel) {
    var next = {}
    for (var k in pendingRoutes) next[k] = pendingRoutes[k]
    next[key] = { channel: channel, at: Date.now() }
    pendingRoutes = next
    send({ cmd: "route", key: key, channel: channel })
  }

  function setEq(key, state) {
    var next = {}
    for (var k in eqs) next[k] = eqs[k]
    next[key] = state
    eqs = next
    send({ cmd: "eq", key: key, state: state })
  }

  function persist() { send({ cmd: "persist" }) }

  function setManageGraph(value) {
    manageGraph = value
    send({ cmd: "setting", key: "manage_graph", value: value })
  }

  function savePos(x, y) {
    savedPos = { x: Math.round(x), y: Math.round(y) }
    send({ cmd: "setting", key: "panel_pos", value: savedPos })
  }

  function takeOver() { send({ cmd: "takeover" }) }

  // Hourly at most unless asked, as the desktop app did.
  function checkUpdate(force) {
    if (update.busy) return
    var now = Date.now()
    if (!force && lastUpdateCheck && now - lastUpdateCheck < 3600 * 1000) return
    lastUpdateCheck = now
    send({ cmd: "updateCheck" })
  }

  function updateClicked() {
    if (update.busy) return
    if (update.state === "outdated") send({ cmd: "updateApply" })
    else checkUpdate(true)
  }

  function nudgeMaster(steps) {
    if (!master) return
    if (masterMuted) setMute("master", false)
    setVolume("master", masterVolume + steps * 0.04)
    send({ cmd: "refresh" })
  }

  function toggleMasterMute() {
    if (!master) return
    setMute("master", !masterMuted)
  }

  // ---- the engine process -----------------------------------------------------

  Process {
    id: engine
    command: ["python3", "-I", root.sourceDir + "/bin/sonus-engine",
      "--plugin-dir", root.sourceDir, "--plugin-id", root.pluginId]
    running: root.sourceDir !== ""
    stdinEnabled: true
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) { root.handleLine(line) }
    }
    stderr: SplitParser {
      splitMarker: "\n"
      onRead: function(line) { console.warn("sonus-engine: " + line) }
    }
    onRunningChanged: {
      if (running) {
        root.send({ cmd: "active", value: root.opened })
        return
      }
      root.engineUp = false
      restartTimer.start()
    }
  }

  // An engine that dies comes back, though not faster than every 3 s.
  Timer {
    id: restartTimer
    interval: 3000
    onTriggered: if (root.sourceDir !== "") engine.running = true
  }

  // ---- window -------------------------------------------------------------------

  readonly property bool opened: windowLoader.item ? windowLoader.item.open : false
  onOpenedChanged: send({ cmd: "active", value: opened })

  function show() {
    if (!windowLoader.item) {
      windowLoader.pendingShow = true
      windowLoader.setSource(Qt.resolvedUrl("Mixer.qml"), { service: root })
      return
    }
    windowLoader.item.show()
  }
  function hide() { if (windowLoader.item) windowLoader.item.hide() }
  function open() { show() }
  function close() { hide() }
  function toggle() {
    if (opened) hide()
    else show()
  }

  Loader {
    id: windowLoader
    property bool pendingShow: false
    onLoaded: {
      if (item && pendingShow) item.show()
      pendingShow = false
    }
  }

  IpcHandler {
    target: "sonus"
    function toggle(): void { root.toggle() }
    function show(): void { root.show() }
    function hide(): void { root.hide() }
    function open(): void { root.show() }
    function close(): void { root.hide() }
    function status(): string {
      return JSON.stringify({
        engine: root.engineUp,
        opened: root.opened,
        status: root.status,
        legacy: root.legacy,
        master: root.master ? Math.round(root.masterVolume * 100) : null,
        apps: root.appsModel.count,
        mixTarget: root.mixTarget
      })
    }
  }
}
