import QtQuick
import Quickshell
import Quickshell.Io
import "ui/Eq.js" as Eq

// The plugin's always-on half. It runs the engine (bin/sonus-engine), which
// owns the virtual channels and keeps every app routed whether the panel is
// open or not, and mirrors the engine's state for the panel in the bar.
//
// The panel itself is the bar widget (Panel.qml), one per monitor; they all
// read this one service, so there is one engine and one poller however many
// bars there are. `omarchy-shell sonus toggle` goes through the shell, which
// opens the panel on the focused monitor.
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
  property string noticeText: ""
  property bool noticeError: false
  property double noticeAt: 0
  property var outputs: []
  property var inputs: []
  property string outputForm: "speaker"
  property string outputLabel: ""
  property string activeProfile: ""
  property int profileEpoch: 0
  // The next config line belongs to a device switch, so the open EQ reloads.
  property bool reloadEq: false
  // The engine's last word on updates: state is unknown | unmanaged |
  // current | outdated | offline | failed; checked is epoch seconds.
  property var update: ({ state: "unknown", local: "", busy: false, applying: false,
    version: "", summary: "", behind: 0, modified: false, message: "", checked: 0 })
  readonly property bool updateAvailable: update.state === "outdated" && !update.busy
  // Optimistic assignments, shown until a snapshot confirms them.
  property var pendingRoutes: ({})

  readonly property var master: channels.master || null
  readonly property real masterVolume: master ? overridden("vol", "master", master.volume) : 0
  readonly property bool masterMuted: master ? overridden("mute", "master", master.muted) : false

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
      outputs = msg.outputs || []
      inputs = msg.inputs || []
      outputForm = msg.outputForm || "speaker"
      outputLabel = msg.outputLabel || ""
      if (msg.activeProfile) activeProfile = msg.activeProfile
      if (msg.profileEpoch) profileEpoch = msg.profileEpoch
      engineUp = true
    } else if (msg.type === "profile") {
      activeProfile = msg.key || activeProfile
      profileEpoch = msg.epoch || profileEpoch
      reloadEq = true
      var applied = {}
      applied["vol:master"] = { value: msg.masterVolume, at: Date.now() }
      applied["mute:master"] = { value: !!msg.masterMuted, at: Date.now() }
      var mixes = msg.channels || {}
      for (var name in mixes) {
        applied["vol:" + name] = { value: mixes[name].volume, at: Date.now() }
        applied["mute:" + name] = { value: !!mixes[name].muted, at: Date.now() }
      }
      overrides = applied
      overrideTimer.restart()
    } else if (msg.type === "config") {
      routes = msg.routes || {}
      var next = {}
      var stored = msg.eq || {}
      for (var k in stored) next[k] = Eq.normalized(stored[k])
      eqs = next
      manageGraph = msg.manageGraph !== false
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
      noticeAt = Date.now()
      noticeTimer.interval = noticeError ? 9000 : 5000
      // A notice from while the panel was shut waits to be seen.
      if (opened) noticeTimer.restart()
    }
  }

  Timer {
    id: noticeTimer
    interval: 5000
    onTriggered: root.noticeText = ""
  }

  function dismissNotice() {
    noticeTimer.stop()
    noticeText = ""
  }

  // ---- commands ---------------------------------------------------------------

  function idsFor(key) {
    if (channels[key]) return [channels[key].node_id]
    var app = appInfo[key]
    return app ? (app.members && app.members.length ? app.members : [app.node_id]) : []
  }

  // What was just set wins over snapshots for a moment: a poll taken before
  // the write landed still carries the old value, and showing it would
  // bounce the slider back.
  property var overrides: ({})

  function override(field, key, value) {
    var next = {}
    for (var k in overrides) next[k] = overrides[k]
    next[field + ":" + key] = { value: value, at: Date.now() }
    overrides = next
    overrideTimer.restart()
  }

  function overridden(field, key, fallback) {
    var o = overrides[field + ":" + key]
    return o && Date.now() - o.at < 1600 ? o.value : fallback
  }

  Timer {
    id: overrideTimer
    interval: 1700
    onTriggered: root.overrides = ({})
  }

  function volumeOf(key) {
    var node = channels[key] || appInfo[key]
    return overridden("vol", key, node ? node.volume : 0)
  }

  function mutedOf(key) {
    var node = channels[key] || appInfo[key]
    return overridden("mute", key, node ? node.muted : false)
  }

  function setVolume(key, value) {
    var ids = idsFor(key)
    value = Math.max(0, Math.min(1, value))
    override("vol", key, value)
    if (ids.length) send({ cmd: "volume", ids: ids, value: value })
  }

  function setMute(key, value) {
    var ids = idsFor(key)
    override("mute", key, !!value)
    if (ids.length) send({ cmd: "mute", ids: ids, value: !!value })
  }

  function adjustVolume(key, delta) {
    if (mutedOf(key) && delta > 0) setMute(key, false)
    setVolume(key, volumeOf(key) + delta)
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

  function takeOver() { send({ cmd: "takeover" }) }

  function selectOutput(id, name) { send({ cmd: "selectOutput", id: id, name: name }) }

  function selectInput(id, name) { send({ cmd: "selectInput", id: id, name: name }) }

  // The engine also checks on its own every few hours. This asks again only
  // when the last answer is older than `minutes`; 0 always asks.
  function checkUpdate(minutes) {
    if (update.busy || update.state === "unmanaged") return
    var checked = Number(update.checked || 0) * 1000
    if (minutes > 0 && checked > 0 && Date.now() - checked < minutes * 60000) return
    send({ cmd: "updateCheck" })
  }

  function applyUpdate() {
    if (update.busy || update.state !== "outdated") return
    var u = {}
    for (var k in update) u[k] = update[k]
    u.busy = true
    u.applying = true
    u.message = ""
    update = u
    send({ cmd: "updateApply" })
  }

  function nudgeMaster(steps) {
    if (master) adjustVolume("master", steps * 0.05)
  }

  function toggleMasterMute() {
    if (master) setMute("master", !mutedOf("master"))
  }

  function appsIn(channel) {
    var out = []
    for (var i = 0; i < appsModel.count; i++) {
      var row = appsModel.get(i)
      if (effectiveChannel(row.key, row.channel) === channel) out.push({ key: row.key, name: row.name, icon: row.icon })
    }
    return out
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
      // The engine can still be talking while a reload tears this down.
      onRead: function(line) { if (root) root.handleLine(line) }
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

  // ---- panel ------------------------------------------------------------------

  // Panels report in, so the engine polls fast only while one is showing.
  property int openPanels: 0
  readonly property bool opened: openPanels > 0
  onOpenedChanged: {
    send({ cmd: "active", value: opened })
    if (!opened || noticeText === "") return
    // Older than a few minutes is no longer news.
    if (Date.now() - noticeAt > 5 * 60000) dismissNotice()
    else noticeTimer.restart()
  }

  // A view to open on ("eq:chat", "settings"), set before the shell opens
  // the panel and taken by whichever panel opens.
  property string requestedView: ""

  function show() { if (shell && typeof shell.summon === "function") shell.summon(pluginId, "{}") }
  function hide() { if (shell && typeof shell.hide === "function") shell.hide(pluginId) }
  function toggle() { if (shell && typeof shell.toggle === "function") shell.toggle(pluginId, "{}") }
  function showView(view) {
    requestedView = view
    if (opened) requestedViewChanged()
    else show()
  }

  IpcHandler {
    target: "sonus"
    function toggle(): void { root.toggle() }
    function show(): void { root.show() }
    function hide(): void { root.hide() }
    function open(): void { root.show() }
    function close(): void { root.hide() }
    function eq(category: string): void { root.showView("eq:" + category) }
    function settings(): void { root.showView("settings") }
    // The panel's Switch: stop the Sonus desktop app and its autostart.
    // Also useful when the app is not running but would start at login.
    function takeover(): string {
      root.takeOver()
      return "switching"
    }
    // Install a waiting update, or look for one.
    function update(): string {
      if (root.update.state === "outdated") {
        root.applyUpdate()
        return "updating to " + (root.update.version || "the latest commit")
      }
      root.checkUpdate(0)
      return "checking"
    }
    function status(): string {
      return JSON.stringify({
        engine: root.engineUp,
        opened: root.opened,
        panels: root.openPanels,
        status: root.status,
        legacy: root.legacy,
        master: root.master ? Math.round(root.masterVolume * 100) : null,
        output: root.outputLabel,
        profile: root.activeProfile,
        apps: root.appsModel.count,
        mixTarget: root.mixTarget,
        version: root.version,
        update: root.update.state,
        updateVersion: root.update.version || null
      })
    }
  }
}
