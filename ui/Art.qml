import QtQuick

// A device or channel drawn big, filling the item by what it draws: one of
// Drawings.js, or AirPods ("airpods-pro", "airpods"), whose mark Batteries
// draws too. Audio.drawingFor picks the name.
Item {
  id: art

  property string name: "speaker"
  property color color: "white"

  readonly property bool airpods: name.indexOf("airpods") === 0

  Drawing {
    visible: !art.airpods
    anchors.fill: parent
    name: art.airpods ? "speaker" : art.name
    color: art.color
  }

  // The mark is fitted to a square by its longer side, so size that side to
  // what the box allows.
  AirPodsIcon {
    id: pods
    visible: art.airpods
    anchors.centerIn: parent
    variant: art.name === "airpods-pro" ? "pro" : "buds"
    color: art.color
    iconSize: Math.max(ink[2], ink[3]) * Math.min(art.width / ink[2], art.height / ink[3])
  }
}
