import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "ui/Glyphs.js" as Glyphs

// The bar's way into Sonus. Click opens the mixer, scroll sets the master
// volume, middle-click mutes it. Everything else is the service's; this
// button only forwards to it.
BarWidget {
  id: root
  moduleName: "io.github.t3lluz.sonus"

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null

  // A replacement bar hands its widgets a facade without serviceFor(); the
  // IPC route answers under any bar, so it stands in.
  function ipc(method) { Quickshell.execDetached(["omarchy-shell", "sonus", method]) }

  // Shape contract for `omarchy-shell shell toggle <id>` routing.
  readonly property bool opened: service ? service.opened : false
  function open() { if (service) service.show(); else ipc("show") }
  function close() { if (service) service.hide(); else ipc("hide") }
  function toggle() { if (service) service.toggle(); else ipc("toggle") }

  readonly property bool showLevel: setting("showLevel", false) === true && !vertical
  readonly property bool muted: service ? service.masterMuted : false
  readonly property int level: service ? Math.round(service.masterVolume * 100) : 0
  readonly property color barFg: bar ? bar.barForeground : Commons.Color.foreground

  property real wheelAcc: 0

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    hasVisualContent: true
    tooltipText: {
      if (!root.service || !root.service.engineUp) return "Sonus: starting"
      var out = "Sonus · " + (root.service.master ? root.service.master.description + " " : "")
        + (root.muted ? "muted" : root.level + "%")
      if (root.service.status) out += "\n" + root.service.status
      return out
    }
    fixedWidth: root.vertical ? -1 : (root.showLevel ? row.implicitWidth + scaledHorizontalMargin * 2 : Style.bar.iconSlot)
    fixedHeight: root.vertical ? Style.bar.iconSlot : -1

    onPressed: function(code) {
      if (code === Qt.MiddleButton) { if (root.service) root.service.toggleMasterMute() }
      else root.toggle()
    }

    onWheelMoved: function(delta) {
      if (!root.service) return
      root.wheelAcc += delta
      var steps = root.wheelAcc > 0 ? Math.floor(root.wheelAcc / 120) : Math.ceil(root.wheelAcc / 120)
      if (steps === 0) return
      root.wheelAcc -= steps * 120
      root.service.nudgeMaster(steps)
    }

    Row {
      id: row
      anchors.centerIn: parent
      spacing: Style.space(5)

      Item {
        width: Style.bar.iconCanvas
        height: Style.bar.iconCanvas
        anchors.verticalCenter: parent.verticalCenter

        OpticalGlyph {
          anchors.fill: parent
          text: root.muted ? Glyphs.volumeOff : Glyphs.sliders
          fontFamily: button.fontFamily
          fontSize: Style.bar.iconFont
          color: root.muted ? Qt.darker(root.barFg, 1.55) : root.barFg
        }

        // Lit while the mixer is open.
        Rectangle {
          visible: root.opened
          width: Math.max(3, Style.space(4))
          height: width
          radius: width / 2
          color: Commons.Color.accent
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.rightMargin: -Style.space(2)
        }
      }

      Text {
        visible: root.showLevel
        anchors.verticalCenter: parent.verticalCenter
        text: root.muted ? "muted" : root.level + "%"
        color: root.muted ? Qt.darker(root.barFg, 1.55) : root.barFg
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
      }
    }
  }
}
