import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "ui"
import "ui/Glyphs.js" as Glyphs
import "ui/Eq.js" as Eq

// Sonus in the bar: a mixer glyph that drops the panel down like every other
// Omarchy panel. Master, the four channels (each with its EQ) and every app
// playing sound, which can be dragged onto a channel or sent there from its
// button. All state lives in the service; this only draws it.
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
    return key === "master" ? "Master" : "Output"
  }

  // ---- views ------------------------------------------------------------------

  property string view: "mixer"

  function setView(next) {
    view = next
    menuKey = ""
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
  }

  // ---- cursor -----------------------------------------------------------------

  // One cursor for keyboard and mouse: "ch:<key>" or "app:<key>".
  property bool cursorActive: false
  property string cursorKey: ""
  property string menuKey: ""

  readonly property var cursorKeys: {
    var keys = ["ch:master"]
    for (var i = 0; i < categories.length; i++) keys.push("ch:" + categories[i].key)
    if (service) {
      service.appsVersion
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
    var rows = [masterRow]
    for (var i = 0; i < channelRepeater.count; i++) rows.push(channelRepeater.itemAt(i))
    for (var j = 0; j < rows.length; j++) {
      var r = rows[j]
      if (!r) continue
      var q = r.mapToItem(stage, 0, 0)
      if (p.x >= q.x && p.x <= q.x + r.width && p.y >= q.y && p.y <= q.y + r.height) return r.key
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
      cursorActive = false
      cursorKey = ""
      endDrag()
      if (flick) flick.contentY = 0
      if (service) service.checkUpdate(false)
      takeRequestedView()
    } else {
      endDrag()
      if (service) service.persist()
    }
  }
  Component.onDestruction: report(false)

  // ---- bar button -------------------------------------------------------------

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.service && root.service.masterMuted ? Glyphs.volumeOff : Glyphs.sliders
    tooltipText: {
      var s = root.service
      if (!s || !s.engineUp) return "Sonus"
      var out = "Sonus · " + (s.master ? s.master.description + " " : "")
        + (s.masterMuted ? "muted" : Math.round(s.masterVolume * 100) + "%")
      return s.status ? out + "\n" + s.status : out
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
    onWheelMoved: function(delta) { if (root.service) root.wheelVolume("master", delta) }
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
          root.setCursor(root.cursorKey !== "" ? root.cursorKey : "ch:master")
          return
        }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0 && root.service) root.service.adjustVolume(root.cursorTarget(), dx * 0.05)
      }
      onActivateRequested: {
        if (root.view !== "mixer" || !root.cursorActive) return
        var target = root.cursorTarget()
        if (root.cursorKey.indexOf("app:") === 0) root.toggleMenu(target)
        else if (target !== "master") root.openEq(target)
        else root.service.setMute("master", !root.service.mutedOf("master"))
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
        else if (key === "m" && target !== "" && root.service) root.service.setMute(target, !root.service.mutedOf(target))
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
            spacing: Style.space(12)

            PanelHero {
              width: parent.width
              title: "Sonus"
              meta: {
                var s = root.service
                if (!s || !s.engineUp) return "STARTING"
                var parts = []
                if (s.master) parts.push(s.master.description)
                if (s.status) parts.push(s.status)
                return parts.join("  ·  ").toUpperCase()
              }
              foreground: root.fg
              fontFamily: root.fontFamily
              iconComponent: Component {
                Text {
                  textFormat: Text.PlainText
                  text: Glyphs.sliders
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }
              trailingControl: Component {
                PanelActionButton {
                  iconText: Glyphs.cog
                  tooltipText: "Settings (s)"
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  onClicked: root.setView("settings")

                  Rectangle {
                    visible: !!root.service && root.service.update.state === "outdated" && !root.service.update.busy
                    width: Style.space(7)
                    height: width
                    radius: width / 2
                    color: Commons.Color.accent
                    anchors.top: parent.top
                    anchors.right: parent.right
                  }
                }
              }
            }

            // The desktop app would fight this panel over routes.
            CursorSurface {
              visible: !!root.service && root.service.legacy
              width: parent.width
              implicitHeight: legacyRow.implicitHeight + Style.spacing.lg
              current: true
              outline: true
              foreground: root.fg
              currentFill: Style.selectedFillFor(Commons.Color.urgent, Commons.Color.urgent)

              Item {
                id: legacyRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Style.space(8)
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

            PanelSeparator { foreground: root.fg }

            Column {
              width: parent.width
              spacing: Style.space(4)

              PanelSectionHeader {
                text: "OUTPUT"
                foreground: root.fg
                fontFamily: root.fontFamily
              }

              ChannelRow {
                id: masterRow
                host: root
                key: "master"
                title: "Master"
                width: parent.width
              }
            }

            PanelSeparator { foreground: root.fg }

            Column {
              width: parent.width
              spacing: Style.space(4)

              PanelSectionHeader {
                text: "CHANNELS"
                foreground: root.fg
                fontFamily: root.fontFamily
              }

              Repeater {
                id: channelRepeater
                model: root.categories

                ChannelRow {
                  required property var modelData
                  host: root
                  key: modelData.key
                  title: modelData.title
                  width: parent.width
                }
              }
            }

            PanelSeparator { foreground: root.fg }

            Column {
              width: parent.width
              spacing: Style.space(4)

              Item {
                width: parent.width
                implicitHeight: appsHeader.implicitHeight

                PanelSectionHeader {
                  id: appsHeader
                  text: "APPS"
                  foreground: root.fg
                  fontFamily: root.fontFamily
                }

                Text {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  visible: !!root.service && root.service.appsModel.count > 0
                  text: "drag onto a channel to assign"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Text {
                visible: !root.service || root.service.appsModel.count === 0
                width: parent.width
                leftPadding: Style.space(6)
                topPadding: Style.space(4)
                bottomPadding: Style.space(4)
                text: "No app audio. Apps that play sound appear here."
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
