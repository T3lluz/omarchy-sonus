import QtQuick
import qs.Commons
import qs.Commons as Commons

// Every surface is the active Omarchy theme: its popup background and text,
// accent, urgent, border, font and corner rounding. The one fixed choice is
// the category hues. They are what tells Game from Chat at a glance, so they
// stay Sonus's own on every theme, a touch brighter on light ones.
QtObject {
  id: theme

  readonly property color fg: Commons.Color.popups.text
  readonly property color bg: Commons.Color.popups.background
  readonly property color accent: Commons.Color.accent
  readonly property color urgent: Commons.Color.urgent
  readonly property color border: Commons.Color.popups.border
  readonly property bool light: (0.2126 * bg.r + 0.7152 * bg.g + 0.0722 * bg.b) > 0.5

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function mix(a, b, t) {
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
  }

  readonly property color well: mix(bg, fg, light ? 0.035 : 0.025)
  readonly property color card: mix(bg, fg, light ? 0.06 : 0.055)
  readonly property color cardHover: mix(bg, fg, light ? 0.1 : 0.085)
  readonly property color rule: alpha(fg, 0.1)
  readonly property color track: alpha(fg, 0.13)
  readonly property color dim: alpha(fg, 0.58)
  readonly property color faint: alpha(fg, 0.34)
  readonly property color thumb: light ? mix(fg, bg, 0.05) : mix(fg, "#ffffff", 0.35)
  readonly property color buttonFill: alpha(fg, 0.07)
  readonly property color buttonHover: alpha(fg, 0.15)

  readonly property string font: Style.font.family
  readonly property int radius: Style.cornerRadius
  readonly property int cardRadius: radius <= 0 ? 0 : Math.max(Style.space(6), radius - Style.space(1))
  readonly property int chipRadius: radius <= 0 ? 0 : Math.max(Style.space(4), Math.round(cardRadius * 0.7))

  function s(px) { return Style.space(px) }

  readonly property var hues: ({
    game: light ? "#1f9e7f" : "#35b697",
    chat: light ? "#3a86d6" : "#539fea",
    media: light ? "#d2468f" : "#e562ae",
    aux: light ? "#7346e6" : "#9273fa"
  })

  function channelColor(key) {
    if (key === "master") return accent
    return hues[key] || dim
  }
}
