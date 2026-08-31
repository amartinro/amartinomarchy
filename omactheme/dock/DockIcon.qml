import QtQuick
import qs.Commons

// One dock icon: app image, hover highlight, running dot, click handling.
// Pinned icons are drag-reorderable: a left press that moves beyond a small
// threshold becomes a drag. While dragging, the icon follows the pointer
// (dragOffsetX transform); the dock applies the new order on release.
Item {
  id: root

  property var entry: null
  property string iconUrl: ""
  property bool running: false
  property real iconSize: 40
  property real cellSize: 50
  property real dotSize: 4
  property int radius: 10
  property bool tahoeMode: false
  property string label: ""
  // Set by the dock delegate: pinned icons can be dragged.
  property bool draggable: false
  // Set by the dock while this icon is the one being dragged.
  property bool isDragged: false
  // Animated scale factor (a Behavior can only live on the item itself, not
  // inside the transform list).
  property real dragScale: 1.0
  property real hoverScale: tahoeMode && iconHover.hovered ? 1.34 : 1.0
  property real launchLift: 0
  readonly property real visualScale: root.dragScale * root.hoverScale
  onIsDraggedChanged: root.dragScale = root.isDragged ? 1.12 : 1.0
  Behavior on dragScale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
  Behavior on hoverScale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
  // Offsets while dragging (pointer follow); 0 at rest.
  property real dragOffsetX: 0
  property real dragOffsetY: 0
  // The Row this icon belongs to (for coordinate mapping during drag).
  property Item row: null

  signal launch()
  signal requestMenu()
  signal dragStartX(real x)
  signal dragMove(real rowX, real winY)
  signal dragEdge()
  signal dragEndX(real x)
  signal dropFiles(var urls)

  width: root.cellSize
  height: root.cellSize
  z: root.isDragged ? 10 : 0

  // Slot moves animate; the duration binding is read at each change, so the
  // dragged icon snaps when the model moves under it mid-drag.
  Behavior on x {
    NumberAnimation {
      duration: root.isDragged ? 0 : 110
      easing.type: Easing.OutQuart
    }
  }

  // Qt6's Scale has no "scale" property (xScale/yScale instead); "origin"
  // lets us scale around the cell center without a translate sandwich.
  transform: [
    Translate { x: root.dragOffsetX; y: root.dragOffsetY },
    Translate { y: root.launchLift },
    Scale {
      xScale: root.visualScale
      yScale: root.visualScale
      origin: Qt.vector3d(root.width / 2, root.height / 2, 0)
    }
  ]

  Rectangle {
    anchors.fill: parent
    radius: root.tahoeMode ? Math.round(root.radius * 0.72) : root.radius
    color: (iconHover.hovered || root.isDragged)
      ? Util.alpha(Color.foreground, root.isDragged ? 0.14 : 0.08)
      : "transparent"
    Behavior on color { ColorAnimation { duration: 90 } }
  }

  Image {
    id: appIcon
    width: root.iconSize
    height: root.iconSize
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: -root.dotSize / 2
    source: root.iconUrl
    fillMode: Image.PreserveAspectFit
    smooth: true
    mipmap: true
  }

  Rectangle {
    id: runningDot
    width: root.dotSize
    height: root.dotSize
    radius: root.dotSize / 2
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 1
    visible: root.running
    color: root.tahoeMode ? "#F4F4F6" : Color.accent
    opacity: root.tahoeMode ? 0.92 : 1
  }

  SequentialAnimation {
    id: launchBounce
    NumberAnimation { target: root; property: "launchLift"; to: -12; duration: 115; easing.type: Easing.OutCubic }
    NumberAnimation { target: root; property: "launchLift"; to: 0; duration: 180; easing.type: Easing.OutBounce }
  }

  Rectangle {
    id: tooltip
    visible: root.tahoeMode && iconHover.hovered && !root.isDragged && root.label.length > 0
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.top
    anchors.bottomMargin: 12
    width: tooltipText.implicitWidth + 18
    height: 27
    radius: 8
    color: "#292B32E8"
    border.width: 1
    border.color: "#FFFFFF24"
    z: 30
    Text {
      id: tooltipText
      anchors.centerIn: parent
      text: root.label
      color: "#F7F7FA"
      font.family: "Sans"
      font.pixelSize: 12
      font.weight: Font.Medium
    }
  }

  // File drop target: dropping a file on the icon opens it with this app.
  DropArea {
    anchors.fill: parent
    onDropped: function(drop) {
      // This Qt build exposes QQuickDragEvent: hasUrls/urls are properties.
      if (drop.hasUrls === true && drop.urls && drop.urls.length > 0) {
        var urls = []
        for (var i = 0; i < drop.urls.length; i++) urls.push(String(drop.urls[i]))
        root.dropFiles(urls)
      }
    }
  }

  HoverHandler { id: iconHover }
  MouseArea {
    id: iconMouse
    anchors.fill: parent
    // hoverEnabled: positionChanged must keep flowing when the pointer is
    // outside the area (defensive; the icon follows the pointer anyway).
    hoverEnabled: true
    cursorShape: root.isDragged ? Qt.ClosedHandCursor : Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    property bool dragging: false
    property real pressX: 0
    property real pressY: 0
    readonly property real dragThreshold: 6

    function rowX(mouse) {
      if (!root.row) return 0
      return root.row.mapFromItem(root, mouse.x, mouse.y).x
    }

    // Pointer position in window-local coordinates. Mapped through the item
// chain (row -> card, which sits at 0,0 in the window) because the item's
// `window` property reads null while a MouseArea grab is active.
    function windowPos(mouse) {
      var card = root.row ? root.row.parent : null
      if (!card) return null
      return card.mapFromItem(root, mouse.x, mouse.y)
    }

    onPressed: function(mouse) {
      if (mouse.button !== Qt.LeftButton) return
      pressX = mouse.x
      pressY = mouse.y
      dragging = false
    }
    // Qt6 motion events carry button = NoButton; held buttons are the
    // `buttons` bitmask.
    onPositionChanged: function(mouse) {
      if ((mouse.buttons & Qt.LeftButton) === 0) return
      if (!dragging) {
        if (!root.draggable) return
        var dx = mouse.x - pressX
        var dy = mouse.y - pressY
        if (dx * dx + dy * dy < dragThreshold * dragThreshold) return
        dragging = true
        root.isDragged = true
        root.dragStartX(mouse.x)
      }
      var p = windowPos(mouse)
      var card = root.row ? root.row.parent : null
      var ch = card ? card.height : 0
      // The pointer at the window edge is leaving the dock (events stop
      // once outside the surface): this is the "drag out to remove" trigger.
      if (p && ch > 0 && (p.y <= 2 || p.y >= ch - 2)) {
        dragging = false
        root.dragEdge()
        return
      }
      root.dragMove(rowX(mouse), p ? p.y : 0)
    }
    onReleased: function(mouse) {
      if (mouse.button !== Qt.LeftButton) return
      if (dragging) {
        dragging = false
        root.dragEndX(rowX(mouse))
      } else {
        if (root.tahoeMode) launchBounce.restart()
        root.launch()
      }
    }
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) root.requestMenu()
    }
  }
}
