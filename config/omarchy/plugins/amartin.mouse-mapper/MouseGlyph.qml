import QtQuick
import qs.Commons

// Mini mouse silhouette. `button` is the evdev code of the button whose
// area gets highlighted (-1 draws the plain body, used in the header).
Item {
  id: root

  property int button: -1
  property color ink: Color.menu.text
  property color highlight: Color.accent

  implicitWidth: 26
  implicitHeight: 40

  // Body
  Rectangle {
    anchors.centerIn: parent
    width: 26
    height: 40
    radius: 13
    color: "transparent"
    border.color: Util.alpha(root.ink, 0.45)
    border.width: 1.5
  }

  // Wheel
  Rectangle {
    anchors.horizontalCenter: parent.horizontalCenter
    y: 6
    width: 3
    height: 9
    radius: 1.5
    color: Util.alpha(root.ink, root.button === 274 ? 1.0 : 0.55)
  }

  // Center divider
  Rectangle {
    anchors.horizontalCenter: parent.horizontalCenter
    y: 18
    width: 1.5
    height: 14
    color: Util.alpha(root.ink, 0.25)
  }

  // Left click
  Rectangle {
    visible: root.button === 272
    x: 2.5
    y: 5
    width: 10
    height: 15
    radius: 5
    color: Util.alpha(root.highlight, 0.9)
  }

  // Right click
  Rectangle {
    visible: root.button === 273
    x: 13.5
    y: 5
    width: 10
    height: 15
    radius: 5
    color: Util.alpha(root.highlight, 0.9)
  }

  // Side button (thumb, back)
  Rectangle {
    visible: root.button === 275
    x: 0
    y: 20
    width: 4
    height: 11
    radius: 2
    color: Util.alpha(root.highlight, 0.9)
  }

  // Extra button (thumb, forward)
  Rectangle {
    visible: root.button === 276
    x: 22
    y: 20
    width: 4
    height: 11
    radius: 2
    color: Util.alpha(root.highlight, 0.9)
  }
}
