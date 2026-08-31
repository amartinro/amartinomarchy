import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Mac-style bottom dock for Omarchy.
//
// App list lives in ~/.config/omarchy/dock.json:
//   { "apps": [ { "id": "firefox" }, { "id": "code", "name": "IDE" }, ... ] }
// Entry fields: id (desktop-entry id, or any label when "command" is set),
// optional name, icon, match[] (extra app_ids treated as running),
// command (custom launch command, bypasses gtk-launch).
//
// Left click: launch or focus. Right click on an icon: move / remove.
// Right click on the dock background: pick an app to add.
// Show/hide: omarchy-dock toggle (SUPER+G) or `omarchy-shell shell toggle local.dock`.
Item {
  id: root

  property var shell: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var manifest: ({})

  // Shell summon/hide/toggle contract (shell.qml drives these via panel IPC).
  property bool shown: true
  readonly property bool opened: shown
  function open(payloadJson) { shown = true }
  function close() { shown = false }

  // ------------------------------------------------------------------ config
  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/dock.json"
  property var entries: []
  readonly property string themeNamePath: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
  property string activeThemeName: ""
  readonly property bool tahoeMode: activeThemeName.trim() === "tahoe-dark"

  function loadThemeName() {
    try { root.activeThemeName = String(themeNameFile.text || "").trim() }
    catch (e) { root.activeThemeName = "" }
  }

  FileView {
    id: themeNameFile
    path: root.themeNamePath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadThemeName()
    onFileChanged: root.loadThemeName()
    onLoadFailed: root.loadThemeName()
  }

  function loadConfig() {
    var raw = ""
    try { raw = configFile.text() } catch (e) { raw = "" }
    var next = []
    try {
      var doc = JSON.parse(raw || "{}")
      var apps = Array.isArray(doc) ? doc : (Array.isArray(doc.apps) ? doc.apps : [])
      for (var i = 0; i < apps.length; i++) {
        var a = apps[i]
        if (!a) continue
        var id = typeof a === "string" ? a : String(a.id || "")
        if (!id) continue
        var entry = { id: id }
        if (typeof a === "object") {
          if (a.name) entry.name = String(a.name)
          if (a.icon) entry.icon = String(a.icon)
          if (a.match) entry.match = a.match
          if (a.command) entry.command = String(a.command)
        }
        next.push(entry)
      }
    } catch (err) {
      console.warn("dock: bad config at " + root.configPath + ": " + err)
    }
    // Skip the rebuild when the content is unchanged (e.g. our own
    // order-add write reloading the list we already hold in memory).
    var prev = ""
    if (root.entries) {
      for (var j = 0; j < root.entries.length; j++) prev += JSON.stringify(root.entries[j]) + "\u0001"
    }
    var now = ""
    for (var k = 0; k < next.length; k++) now += JSON.stringify(next[k]) + "\u0001"
    if (prev === now) return
    root.entries = next
    root.refreshRunning()
    root.loadHyprLook()
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadConfig()
    onFileChanged: root.loadConfig()
    onLoadFailed: root.loadConfig()
  }

  // Hyprland look'n'feel sources (defaults first, user file overrides).
  FileView {
    id: hyprDefaultLook
    path: root.omarchyPath + "/default/hypr/looknfeel.lua"
    printErrors: false
    onLoaded: root.loadHyprLook()
    onLoadFailed: root.loadHyprLook()
  }
  FileView {
    id: hyprUserLook
    path: Quickshell.env("HOME") + "/.config/hypr/looknfeel.lua"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadHyprLook()
    onFileChanged: root.loadHyprLook()
    onLoadFailed: root.loadHyprLook()
  }

  // Explicit re-read (omarchy-dock reload / `omarchy-shell shell call local.dock reload`).
  function reload(payloadJson) { configFile.reload(); root.loadHyprLook() }
  

  // ------------------------------------------------------------------ geometry
  readonly property real iconSize: tahoeMode ? 48 : Style.space(40)
  readonly property real cellPad: tahoeMode ? 7 : Style.space(5)
  readonly property real rowGap: tahoeMode ? 2 : Style.space(4)
  readonly property real cardPad: tahoeMode ? 8 : Style.space(10)
  readonly property real edgeGap: tahoeMode ? 10 : Style.space(8)
  readonly property real dotSize: tahoeMode ? 4 : Style.space(4)

  // Border/radius mirror Hyprland's window decoration (focused window border
  // size and window rounding), read from the hyprland look'n'feel files.
  property real hyprBorderWidth: 2
  property int hyprRounding: 8
  readonly property int cardRadius: root.tahoeMode ? 20 : root.hyprRounding

  function parseHyprInt(text, key) {
    if (!text) return -1
    var lines = String(text).split("\n")
    var re = new RegExp("\\b" + key + "\\s*=\\s*(\\d+)")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].replace(/^\s+/, "")
      if (line.indexOf("--") === 0) continue
      var m = re.exec(line)
      if (m) return parseInt(m[1], 10)
    }
    return -1
  }
  function loadHyprLook() {
    var border = 2
    var rounding = 8
    try {
      var t = hyprDefaultLook.text
      var b = root.parseHyprInt(t, "border_size"); if (b >= 0) border = b
      var r = root.parseHyprInt(t, "rounding"); if (r >= 0) rounding = r
    } catch (e) { }
    try {
      var u = hyprUserLook.text
      var b2 = root.parseHyprInt(u, "border_size"); if (b2 >= 0) border = b2
      var r2 = root.parseHyprInt(u, "rounding"); if (r2 >= 0) rounding = r2
    } catch (e) { }
    root.hyprBorderWidth = border
    root.hyprRounding = rounding
  }

  readonly property real cellSize: root.iconSize + root.cellPad * 2
  readonly property int entryCount: root.entries.length
  readonly property int runningCount: root.runningApps.length
  readonly property bool hasSeparator: root.entryCount > 0 && root.runningCount > 0
  readonly property real separatorWidth: Style.spacing.hairline
  readonly property real cardWidth: root.computeCardWidth()
  function computeCardWidth() {
    // Guarded: this binding can run before later-declared props are ready.
    var cell = Number(root.cellSize) || 0
    var gap = Number(root.rowGap) || 0
    var pad = Number(root.cardPad) || 0
    var pinned = Number(root.entryCount) || 0
    var running = root.runningApps ? root.runningApps.length : 0
    var total = pinned * cell
    if (pinned > 0) total += (pinned - 1) * gap
    if (pinned > 0 && running > 0) total += gap + (Number(root.separatorWidth) || 1) + gap
    if (running > 0) total += running * cell + (running - 1) * gap
    if (total === 0) return cell * 1.6
    return total + pad * 2
  }
  readonly property real cardHeight: root.cellSize + root.cardPad * 2

  // ------------------------------------------------------------------ entry helpers
  function entryName(entry) {
    var v = String(entry.name || "")
    return v.length > 0 ? v : String(entry.id || "")
  }

  function entryIconName(entry) {
    return String(entry.icon || entry.id || "")
  }

  function iconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return Quickshell.iconPath("application-x-executable", true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var themed = Quickshell.iconPath(value, true)
    return themed.length > 0 ? themed : Quickshell.iconPath("application-x-executable", true)
  }

  // ------------------------------------------------------------------ running apps
  // Dots for pinned entries that have a window open.
  property var runningKeys: ({})
  // Open apps that are NOT pinned: [{appId, name, title, icon, desktopId, toplevels}]
  // Stable order: existing apps keep their slot, new ones append, closed ones drop.
  property var runningApps: []

  function entryCandidates(entry) {
    var out = []
    var id = String(entry.id || "").toLowerCase().replace(/\.desktop$/, "")
    if (id.length >= 2) out.push(id)
    var ic = String(entry.icon || "").toLowerCase()
    if (ic.length >= 2) out.push(ic)
    var match = entry.match
    if (Array.isArray(match)) {
      for (var i = 0; i < match.length; i++) {
        var m = String(match[i]).toLowerCase()
        if (m.length >= 2) out.push(m)
      }
    }
    return out
  }

  function matchesAppId(entry, appId) {
    var app = String(appId || "").toLowerCase()
    if (app.length < 2) return false
    var cands = root.entryCandidates(entry)
    for (var i = 0; i < cands.length; i++) {
      var cand = cands[i]
      if (app === cand) return true
      if (cand.length >= 4 && (app.indexOf(cand) !== -1 || cand.indexOf(app) !== -1)) return true
    }
    return false
  }

  function toplevelList() {
    try { return ToplevelManager.toplevels.values || [] } catch (e) { return [] }
  }

  // Desktop entry (if any) whose id/icon matches a running app's appId.
  function desktopForAppId(appId) {
    var app = String(appId || "").toLowerCase()
    if (app.length < 2) return null
    var values = []
    try { values = DesktopEntries.applications.values || [] } catch (e) { return null }
    for (var i = 0; i < values.length; i++) {
      var e = values[i]
      var id = String(e.id || "").toLowerCase().replace(/\.desktop$/, "")
      if (!id) continue
      if (app === id || (id.length >= 4 && (app.indexOf(id) !== -1 || id.indexOf(app) !== -1))) return e
    }
    return null
  }

  // {runningKeys, runningApps} for the current window set.
  function refreshRunning() {
    var entries = root.entries
    var toplevels = root.toplevelList()

    var keys = {}
    var groups = {}      // appId -> {title, toplevels:[]}
    var order = []       // first-seen order of unpinned appIds
    for (var t = 0; t < toplevels.length; t++) {
      var toplevel = toplevels[t]
      var appId = String(toplevel.appId || "")
      if (appId.length < 2) continue
      var pinnedHit = ""
      for (var e = 0; e < entries.length; e++) {
        if (root.matchesAppId(entries[e], appId)) {
          keys[String(entries[e].id)] = true
          pinnedHit = String(entries[e].id)
          break
        }
      }
      if (pinnedHit) continue
      if (!groups[appId]) {
        groups[appId] = { title: String(toplevel.title || ""), toplevels: [] }
        order.push(appId)
      }
      groups[appId].toplevels.push(toplevel)
      if (String(toplevel.title || "").length > 0) groups[appId].title = String(toplevel.title)
    }

    // Keep the previous order for surviving apps; append newcomers at the end.
    // Survivors keep their object identity (in-place update) so the Repeater
    // does not rebuild icons on every focus change.
    var next = []
    var previous = root.runningApps
    for (var p = 0; p < previous.length; p++) {
      var prev = previous[p]
      var prevId = String(prev.appId)
      if (groups[prevId]) {
        prev.toplevels = groups[prevId].toplevels
        prev.title = groups[prevId].title
        next.push(prev)
      }
    }
    for (var o = 0; o < order.length; o++) {
      var newId = order[o]
      if (!groups[newId]) continue
      var seen = false
      for (var n = 0; n < next.length; n++)
        if (String(next[n].appId) === newId) { seen = true; break }
      if (!seen) next.push(root.buildRunningApp(newId, groups[newId]))
    }

    root.runningKeys = keys
    root.runningApps = next
  }

  function buildRunningApp(appId, group) {
    var desktop = root.desktopForAppId(appId)
    var name = desktop ? String(desktop.name || "") : ""
    if (!name) name = String(group.title || appId)
    var icon = desktop ? String(desktop.icon || "") : ""
    var app = {
      appId: appId,
      name: name,
      title: String(group.title || ""),
      icon: icon,
      desktopId: desktop ? String(desktop.id || "") : "",
      toplevels: group.toplevels
    }
    return app
  }

  function isRunning(entry) {
    return root.runningKeys[String(entry.id)] === true
  }

  function runningIconUrl(app) {
    if (app.icon) return root.iconSource(app.icon)
    return root.iconSource(app.appId)
  }

  function focusApp(app) {
    var toplevels = app.toplevels
    if (!toplevels || toplevels.length === 0) return
    if (root.tahoeMode) Quickshell.execDetached(["tahoe-window", "restore-app", String(app.appId || "")])
    var active = ToplevelManager.activeToplevel
    var target = toplevels[0]
    for (var i = 0; i < toplevels.length; i++)
      if (toplevels[i] === active) { target = toplevels[i]; break }
    try { target.activate() } catch (e) { }
  }

  function closeApp(app) {
    var toplevels = app.toplevels
    if (!toplevels) return
    for (var i = toplevels.length - 1; i >= 0; i--) {
      try { toplevels[i].close() } catch (e) { }
    }
  }

  function pinApp(app) {
    // Pin by the .desktop id when we know it, falling back to the raw appId so
    // the entry still matches its windows via the explicit "match" field.
    var id = app.desktopId ? String(app.desktopId) : String(app.appId)
    root.dockCli(["add", id, "--match", String(app.appId)])
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { root.refreshRunning() }
  }
  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() { root.refreshRunning() }
  }

  // ------------------------------------------------------------------ actions
  function launchOrFocus(entry) {
    var id = String(entry.id || "")
    if (!id) return
    var toplevels = root.toplevelList()
    for (var t = 0; t < toplevels.length; t++) {
      if (root.matchesAppId(entry, String(toplevels[t].appId || ""))) {
        if (root.tahoeMode) Quickshell.execDetached(["tahoe-window", "restore-app", String(toplevels[t].appId || "")])
        try { toplevels[t].activate() } catch (e) { }
        return
      }
    }
    var command = String(entry.command || "")
    if (command.length > 0) {
      Util.execDetached(Util.shellQuote(command))
    } else {
      Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(id + ".desktop"))
    }
  }

  // Config mutations go through the CLI so dock.json stays the single source
  // of truth; FileView's watchChanges reloads the list after each write.
  function dockCli(args) {
    var cmd = ["omarchy-dock"]
    for (var i = 0; i < args.length; i++) cmd.push(String(args[i]))
    Quickshell.execDetached(cmd)
  }

  function addEntry(desktopId) { root.dockCli(["add", desktopId]) }
  function removeEntry(desktopId) { root.dockCli(["remove", desktopId]) }
  function moveEntry(desktopId, direction) { root.dockCli(["move", desktopId, direction]) }

  // File drop on an icon: open the files with that app. Pinned entries use
  // their .desktop id (gtk-launch routes to a running instance when the app
  // supports activation); custom-command entries launch their command.
  function openFilesWith(entry, urls) {
    if (!entry || !urls || urls.length === 0) return
    var id = String(entry.desktopId || entry.id || entry.appId || "")
    var command = String(entry.command || "")
    var quoted = []
    for (var i = 0; i < urls.length; i++) {
      var u = String(urls[i] || "")
      if (u.indexOf("file://") === 0) u = u.substring(7)
      if (u.length > 0) quoted.push(Util.shellQuote(u))
    }
    if (quoted.length === 0) return
    var files = quoted.join(" ")
    if (command.length > 0) {
      Util.execDetached(Util.shellQuote(command) + " " + files)
    } else if (id.length > 0) {
      Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(id + ".desktop") + " " + files)
    }
  }

  // ------------------------------------------------------------------ drag reorder
  // Pinned icons are drag-reorderable. While dragging, `dragIndex` is the slot
  // the pointer is over; on every change the in-memory order updates (the Row
  // animates icons into place) and on release the order is persisted.
  // `draggingItem` is the delegate being dragged (the Repeater in this build
  // does not fill a delegate `index` property, so slots are tracked logically
  // and the initial slot is derived from the item's stable x at press time).
property var draggingItem: null
  property int dragIndex: -1
  property int dragFromIndex: -1
  property real grabOffsetX: 0
  property real dragLayoutCenterY: 0

  function startDrag(item, grabX) {
    if (!item) return
    var cell = root.cellSize + root.rowGap
    var idx = Math.round(Number(item.x) / cell)
    if (idx < 0) idx = 0
    if (idx > root.entries.length - 1) idx = root.entries.length - 1
    root.draggingItem = item
    root.dragFromIndex = idx
    root.dragIndex = idx
    root.grabOffsetX = Number(grabX) || 0
    // Layout center in window coords, measured once before any offset is
    // applied (mapFromItem would otherwise include the drag transform).
    root.dragLayoutCenterY = dockCard.mapFromItem(item, 0, 0).y + root.cellSize / 2
    root.dragHover(Number(item.x) + root.grabOffsetX)
  }

  // While dragging: the icon follows the pointer in X and Y (no model
  // changes); the drop slot is just tracked from the pointer position.
  function dragHover(rowX, winY) {
    if (root.draggingItem === null) return
    if (isNaN(Number(rowX))) return
    var count = root.entries.length
    if (count === 0) return
    var cell = root.cellSize + root.rowGap
    var leftEdge = rowX - root.grabOffsetX
    var maxLeft = (count - 1) * cell
    if (leftEdge < 0) leftEdge = 0
    if (leftEdge > maxLeft) leftEdge = maxLeft
    root.draggingItem.dragOffsetX = leftEdge - root.dragFromIndex * cell
    // Vertical follow: the icon's center tracks the pointer, so it visibly
    // lifts toward the edge it is being dragged to. The offset is computed
    // from the layout center measured at drag start (not mapFromItem, which
    // would include the transform and oscillate). Clamped so the icon stays
    // fully inside the window.
    if (winY !== undefined && !isNaN(Number(winY))) {
      var offY = Number(winY) - root.dragLayoutCenterY
      var limit = Number(root.cardPad) || 10
      if (offY < -limit) offY = -limit
      if (offY > limit) offY = limit
      root.draggingItem.dragOffsetY = offY
    }
    var target = Math.round(leftEdge / cell)
    if (target < 0) target = 0
    if (target > count - 1) target = count - 1
    if (target !== root.dragIndex) root.dragIndex = target
  }

  function endDrag(rowX) {
    if (root.draggingItem === null) return
    root.dragHover(rowX)
    var from = root.dragFromIndex
    var to = root.dragIndex
    if (isNaN(to)) to = from
    var item = root.draggingItem
    // Clear the drag state BEFORE touching the model: replacing entries
    // destroys the delegates, and the item must not be used afterwards
    // (a QML function call on a destroyed context throws).
    root.draggingItem = null
    root.dragIndex = -1
    root.dragFromIndex = -1
    root.grabOffsetX = 0
    if (to !== from && root.entries.length > 1) {
      var e = root.entries.slice()
      var moved = e.splice(from, 1)[0]
      e.splice(to, 0, moved)
      root.entries = e
      var ids = []
      for (var i = 0; i < e.length; i++) ids.push(String(e[i].id))
      root.dockCli(["order"].concat(ids))
    } else if (item) {
      // No move: settle the floating icon back in its slot.
      item.dragOffsetX = 0
      item.dragOffsetY = 0
    }
  }

  // Dropping outside the window removes the app from the dock.
  function dropOutsideDrag() {
    if (root.draggingItem === null) return
    var item = root.draggingItem
    var id = String(item.entry.id || "")
    item.isDragged = false
    item.dragOffsetX = 0
    item.dragOffsetY = 0
    root.draggingItem = null
    root.dragIndex = -1
    root.dragFromIndex = -1
    root.grabOffsetX = 0
    if (id) root.removeEntry(id)
  }

  // ------------------------------------------------------------------ popups
  property bool menuOpen: false
  property var menuEntry: null
  property bool menuIsRunning: false
  property real menuAnchorX: 0
  property bool pickerOpen: false
  property string pickerQuery: ""

  function openMenu(entry, anchorX) {
    root.menuEntry = entry
    root.menuIsRunning = false
    root.menuAnchorX = anchorX
    root.pickerOpen = false
    root.menuOpen = true
  }
  function openRunningMenu(app, anchorX) {
    root.menuEntry = app
    root.menuIsRunning = true
    root.menuAnchorX = anchorX
    root.pickerOpen = false
    root.menuOpen = true
  }
  function openPicker() {
    root.menuOpen = false
    root.pickerQuery = ""
    root.pickerOpen = true
  }
  function closePopups() {
    root.menuOpen = false
    root.pickerOpen = false
  }

  // Desktop entries not already in the dock, filtered by pickerQuery.
  function pickerRows(limit) {
    var rows = []
    var inDock = {}
    var entries = root.entries
    for (var d = 0; d < entries.length; d++) inDock[String(entries[d].id)] = true
    var values = []
    try { values = DesktopEntries.applications.values || [] } catch (e) { return rows }
    var query = root.pickerQuery.trim().toLowerCase()
    for (var i = 0; i < values.length; i++) {
      var entry = values[i]
      var id = String(entry.id || "")
      if (!id || inDock[id]) continue
      if (query.length > 0) {
        var hay = (String(entry.name || "") + " " + id + " " + String(entry.genericName || "")).toLowerCase()
        if (hay.indexOf(query) === -1) continue
      }
      rows.push(entry)
      if (rows.length >= limit) break
    }
    return rows
  }

  // ------------------------------------------------------------------ dock window
  PanelWindow {
    id: dockWindow

    visible: root.shown && !remapGuard.remapping
    exclusionMode: root.shown ? ExclusionMode.Auto : ExclusionMode.Ignore
    color: "transparent"
    surfaceFormat.opaque: false
    WlrLayershell.namespace: "local-dock"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: false
      bottom: true
      left: true
      right: true
    }
    margins {
      top: 0
      bottom: root.edgeGap
      left: 0
      right: 0
    }
    implicitWidth: 0
    implicitHeight: root.cardHeight + (root.tahoeMode ? 42 : 0)

    ScreenMoveRemap {
      id: remapGuard
      window: dockWindow
    }

    // Right click on empty dock area: open the add-app picker.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.RightButton
      onClicked: function(mouse) { root.openPicker() }
    }

    // If the pointer leaves the whole window mid-drag, the compositor stops
    // delivering motion and the release may never arrive: finalize the drop
    // at the last known slot so the icon can't get stuck in drag state.
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      onExited: {
        if (root.draggingItem !== null) root.dropOutsideDrag()
      }
    }

    BorderSurface {
      id: dockCard
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      width: root.cardWidth
      height: root.cardHeight
      color: root.tahoeMode ? "#24262DC7" : Color.popups.background
      borderSpec: Border.localOrSurfaceSpec("popups", "border",
        root.tahoeMode ? "#FFFFFF2B" : Color.popups.border,
        root.tahoeMode ? "#FFFFFF2B" : Color.popups.border,
        root.tahoeMode ? 1 : root.hyprBorderWidth)
      radius: root.cardRadius

      Rectangle {
        visible: root.tahoeMode
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 1
        height: 1
        radius: 1
        color: "#FFFFFF30"
      }

      Row {
        id: iconRow
        anchors.centerIn: parent
        spacing: root.rowGap

        // Pinned apps (from dock.json), drag-reorderable.
        Repeater {
          model: root.entries
          delegate: DockIcon {
            id: dockIcon
            required property var modelData
            entry: modelData
            iconUrl: root.iconSource(root.entryIconName(modelData))
            running: root.isRunning(modelData)
            iconSize: root.iconSize
            cellSize: root.cellSize
            dotSize: root.dotSize
            radius: root.cardRadius
            tahoeMode: root.tahoeMode
            label: root.entryName(modelData)
            draggable: true
            row: iconRow
            isDragged: root.draggingItem === dockIcon
            onLaunch: root.launchOrFocus(modelData)
            onRequestMenu: {
              var point = dockWindow.contentItem.mapFromItem(dockIcon, dockIcon.width / 2, 0)
              root.openMenu(modelData, point.x)
            }
            onDragStartX: function(x) { root.startDrag(dockIcon, x) }
            onDragMove: function(rowX, winY) { root.dragHover(rowX, winY) }
            onDragEdge: root.dropOutsideDrag()
            onDragEndX: function(rowX) { root.endDrag(rowX) }
            onDropFiles: function(urls) { root.openFilesWith(dockIcon.entry, urls) }
          }
        }

        // Separator between pinned and running (only when both exist).
        Rectangle {
          visible: root.hasSeparator
          width: root.separatorWidth
          height: root.iconSize
          radius: root.separatorWidth / 2
          color: Util.alpha(Color.foreground, 0.25)
        }

        // Open apps that are not pinned.
        Repeater {
          model: root.runningApps
          delegate: DockIcon {
            id: runningIcon
            required property var modelData
            entry: modelData
            iconUrl: root.runningIconUrl(modelData)
            running: false
            iconSize: root.iconSize
            cellSize: root.cellSize
            dotSize: root.dotSize
            radius: root.cardRadius
            tahoeMode: root.tahoeMode
            label: String(modelData.name || modelData.appId || "")
            onLaunch: root.focusApp(modelData)
            onRequestMenu: {
              var point = dockWindow.contentItem.mapFromItem(runningIcon, runningIcon.width / 2, 0)
              root.openRunningMenu(modelData, point.x)
            }
            onDropFiles: function(urls) { root.openFilesWith(modelData, urls) }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------------ icon context menu
  PopupWindow {
    id: menuWindow

    visible: root.menuOpen && root.menuEntry !== null
    color: "transparent"
    implicitWidth: menuCard.implicitWidth
    implicitHeight: menuCard.implicitHeight

    anchor {
      id: menuAnchor
      window: dockWindow
      adjustment: PopupAdjustment.Slide
      edges: Edges.Bottom | Edges.Left
      gravity: Edges.Top | Edges.Right
      rect.width: 1
      rect.height: 1

      onAnchoring: {
        if (!root.menuOpen) return
        var popupWidth = menuWindow.implicitWidth
        var popupHeight = menuWindow.implicitHeight
        var localX = root.menuAnchorX - popupWidth / 2
        localX = Math.max(4, Math.min(localX, dockWindow.width - popupWidth - 4))
        var localY = -popupHeight - 8
        menuAnchor.rect.x = Math.round(localX)
        menuAnchor.rect.y = Math.round(localY)
      }
    }

    BorderSurface {
      id: menuCard
      width: Style.space(220)
      color: Color.menu.background
      borderSpec: Border.localOrSurfaceSpec("menu", "border", Color.menu.border, Color.menu.border, 1)
      radius: root.cardRadius
      padding: Style.spacing.xs
      implicitWidth: width
      implicitHeight: menuContent.implicitHeight + 2 * Style.spacing.xs

      Column {
        id: menuContent
        anchors.fill: parent
        anchors.topMargin: menuCard.contentTopInset
        anchors.rightMargin: menuCard.contentRightInset
        anchors.bottomMargin: menuCard.contentBottomInset
        anchors.leftMargin: menuCard.contentLeftInset
        spacing: Style.spacing.xxs

        Text {
          id: menuTitle
          width: parent.width
          text: root.menuIsRunning
            ? String(root.menuEntry.name || "")
            : (root.menuEntry ? root.entryName(root.menuEntry) : "")
          elide: Text.ElideRight
          color: Color.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Text {
          id: menuSubtitle
          width: parent.width
          visible: root.menuIsRunning && root.menuEntry !== null
            && String(root.menuEntry.title || "") !== String(root.menuEntry.name || "")
          text: root.menuEntry ? String(root.menuEntry.title || "") : ""
          elide: Text.ElideRight
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Math.round(Style.font.body * 0.9)
        }

        component MenuRow: Item {
          id: menuRowBase
          property string rowText: ""
          property bool rowEnabled: true
          readonly property real rowHeight: Style.spacing.popupRowHeight

          implicitHeight: rowHeight
          visible: rowEnabled

          Rectangle {
            anchors.fill: parent
            radius: Math.max(4, Math.round(root.cardRadius / 2))
            color: rowHover.hovered && rowEnabled ? Color.menu.selectedBackground : "transparent"
            Behavior on color { ColorAnimation { duration: 90 } }
          }
          Text {
            id: rowLabel
            anchors.verticalCenter: parent.verticalCenter
            x: Style.spacing.lg
            text: menuRowBase.rowText
            color: rowEnabled ? Color.menu.text : Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
          HoverHandler { id: rowHover }
          MouseArea {
            anchors.fill: parent
            enabled: rowEnabled
            cursorShape: Qt.PointingHandCursor
            onClicked: menuRowBase.rowClicked()
          }
          signal rowClicked()
        }

        MenuRow {
          width: parent.width
          rowText: "Move left"
          rowEnabled: !root.menuIsRunning && root.menuEntry
            && root.entries.indexOf(root.menuEntry) > 0
          onRowClicked: {
            if (root.menuEntry) root.moveEntry(root.menuEntry.id, "left")
            root.closePopups()
          }
        }
        MenuRow {
          width: parent.width
          rowText: "Move right"
          rowEnabled: !root.menuIsRunning && root.menuEntry
            && root.entries.indexOf(root.menuEntry) < root.entries.length - 1
          onRowClicked: {
            if (root.menuEntry) root.moveEntry(root.menuEntry.id, "right")
            root.closePopups()
          }
        }
        MenuRow {
          width: parent.width
          rowText: "Remove from dock"
          rowEnabled: !root.menuIsRunning
          onRowClicked: {
            if (root.menuEntry) root.removeEntry(root.menuEntry.id)
            root.closePopups()
          }
        }
        MenuRow {
          width: parent.width
          rowText: "Pin to dock"
          rowEnabled: root.menuIsRunning
          onRowClicked: {
            if (root.menuEntry) root.pinApp(root.menuEntry)
            root.closePopups()
          }
        }
        MenuRow {
          width: parent.width
          rowText: "Close window"
          rowEnabled: root.menuIsRunning
          onRowClicked: {
            if (root.menuEntry) root.closeApp(root.menuEntry)
            root.closePopups()
          }
        }
      }
    }
  }

  // ------------------------------------------------------------------ add-app picker
  PopupWindow {
    id: pickerWindow

    visible: root.pickerOpen
    color: "transparent"
    implicitWidth: Style.space(300)
    implicitHeight: pickerCard.implicitHeight

    anchor {
      id: pickerAnchor
      window: dockWindow
      adjustment: PopupAdjustment.Slide
      edges: Edges.Bottom | Edges.Left
      gravity: Edges.Top | Edges.Right
      rect.width: 1
      rect.height: 1

      onAnchoring: {
        if (!root.pickerOpen) return
        var popupWidth = pickerWindow.implicitWidth
        var popupHeight = pickerWindow.implicitHeight
        var localX = dockWindow.width / 2 - popupWidth / 2
        var localY = -popupHeight - 8
        pickerAnchor.rect.x = Math.round(localX)
        pickerAnchor.rect.y = Math.round(localY)
      }
    }

    BorderSurface {
      id: pickerCard
      width: Style.space(300)
      color: Color.menu.background
      borderSpec: Border.localOrSurfaceSpec("menu", "border", Color.menu.border, Color.menu.border, 1)
      radius: root.cardRadius
      padding: Style.spacing.sm
      implicitHeight: pickerContent.implicitHeight + 2 * Style.spacing.sm

      Column {
        id: pickerContent
        anchors.fill: parent
        anchors.topMargin: pickerCard.contentTopInset
        anchors.rightMargin: pickerCard.contentRightInset
        anchors.bottomMargin: pickerCard.contentBottomInset
        anchors.leftMargin: pickerCard.contentLeftInset
        spacing: Style.spacing.sm

        TextField {
          id: pickerSearch
          width: pickerContent.width
          focus: true
          text: root.pickerQuery
          onTextChanged: root.pickerQuery = text
          placeholderText: "Add app — type to search"
          color: Color.menu.text
          placeholderTextColor: Color.muted
          selectionColor: Color.menu.selectedBackground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          background: Rectangle {
            radius: Math.max(4, Math.round(root.cardRadius / 2))
            color: Color.popups.background
            border.width: pickerSearch.activeFocus ? 1 : 0
            border.color: Color.menu.selectedBorder
          }
        }

        Column {
          id: pickerList
          width: pickerContent.width

          Repeater {
            model: root.pickerRows(6)

            delegate: Item {
              required property var modelData
              width: pickerList.width
              height: Style.spacing.popupRowHeight + Style.space(20)

              Rectangle {
                anchors.fill: parent
                radius: Math.max(4, Math.round(root.cardRadius / 2))
                color: rowHover.hovered ? Color.menu.selectedBackground : "transparent"
                Behavior on color { ColorAnimation { duration: 90 } }
              }
              Image {
                x: Style.spacing.sm
                width: Style.space(18)
                height: Style.space(18)
                anchors.verticalCenter: parent.verticalCenter
                source: root.iconSource(String(modelData.icon || modelData.id || ""))
                fillMode: Image.PreserveAspectFit
                smooth: true
              }
              Text {
                x: Style.space(18) + Style.spacing.lg
                anchors.verticalCenter: parent.verticalCenter
                width: pickerList.width - x - Style.spacing.sm
                text: String(modelData.name || modelData.id)
                elide: Text.ElideRight
                color: Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
              HoverHandler { id: rowHover }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.addEntry(String(modelData.id))
                  root.closePopups()
                }
              }
            }
          }
        }

        Text {
          width: pickerContent.width
          visible: root.pickerOpen && root.pickerRows(6).length === 0
          text: root.pickerQuery.trim().length > 0 ? "No matching apps" : "Nothing to add"
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }

  // Clicking outside either popup dismisses it.
  HyprlandFocusGrab {
    active: root.menuOpen || root.pickerOpen
    windows: [dockWindow, menuWindow, pickerWindow]
    onCleared: root.closePopups()
  }
}
