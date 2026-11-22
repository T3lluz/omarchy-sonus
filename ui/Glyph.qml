import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

// The icon in every part of the panel kit. The kit hands it a Nerd Font
// glyph, `icon` being the character. Where the glyph has a pixel icon
// (Model.PIXEL_GLYPHS) that is drawn instead, so the kit's icons match the
// rooms'; anything else is typed. The other kit files are the same in all
// four plugins; this one is each plugin's own.
Item {
  id: glyph

  property string icon: ""
  property real size: Style.font.body
  property color color: Commons.Color.foreground
  property string fontFamily: Style.font.family

  readonly property string pixel: Model.pixelFor(icon)

  implicitWidth: size
  implicitHeight: size

  PixelIcon {
    visible: glyph.pixel !== ""
    anchors.centerIn: parent
    name: glyph.pixel
    size: glyph.size
    color: glyph.color
  }

  Text {
    visible: glyph.pixel === ""
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: glyph.icon
    color: glyph.color
    font.family: glyph.fontFamily
    font.pixelSize: glyph.size
  }
}
