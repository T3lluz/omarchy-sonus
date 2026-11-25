import QtQuick
import qs.Commons
import qs.Commons as Commons

// Panel kit: a quiet line. A hint under a control, what a choice does, an
// empty section's "nothing here yet". Give it a width to wrap; a long word
// or path breaks rather than running out of the panel.
MonoText {
  property color foreground: Commons.Color.foreground

  step: "small"
  textFormat: Text.PlainText
  wrapMode: Text.Wrap
  color: foreground
  opacity: 0.55
}
