import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool closingFromHost: false
  property var device: ({ connected: false, path: "", buttons: [] })
  property var mappings: ({})     // code(string) -> command
  property var selection: ({})    // code(string) -> dropdown value ("__custom__" or preset)
  property var customText: ({})   // code(string) -> custom command text
  property string status: ""
  property bool applying: false

  // Live button monitoring
  property var livePressed: []    // codes currently held down
  property var seenButtons: []    // codes pressed since the overlay opened
  property int lastRel: -1        // last relative axis code (wheel, hwheel…)
  property string lastUnknown: "" // last button code outside the known list

  // ------------------------------------------------------------------ paths
  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: home + "/.config/omarchy/plugins/amartin.mouse-mapper"
  // State lives OUTSIDE the plugin dir: the shell hot-reloads the plugin on
  // any file change there, which would close the overlay on every save.
  readonly property string stateFile: home + "/.local/state/omarchy/mouse-mapper.json"
  readonly property string mouseLua: home + "/.config/hypr/mouse.lua"

  // ------------------------------------------------------------------ theme
  // The window is a normal Hyprland-decorated surface (title bar + buttons
  // from the active theme), so it uses an opaque window background instead
  // of the translucent menu wash.
  property color windowBackground: Util.alpha(Color.menu.background, 1.0)
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  readonly property int contentMargin: Style.space(22)
  readonly property int windowWidth: Style.space(620)
  readonly property int windowHeight: Style.space(680)
  readonly property int minWindowWidth: Style.space(540)
  readonly property int minWindowHeight: Style.space(420)
  property int contentWidth: window.width - contentMargin * 2

  // ------------------------------------------------------------------ data
  readonly property var buttonDefs: [
    { code: 272, name: "Clic izquierdo", hint: "Botón principal" },
    { code: 273, name: "Clic derecho", hint: "Botón secundario" },
    { code: 274, name: "Clic central", hint: "Pulsar la rueda" },
    { code: 275, name: "Pulgar arriba", hint: "Atrás" },
    { code: 276, name: "Pulgar abajo", hint: "Adelante" }
  ]

  readonly property var actions: [
    { value: "", label: "Sin acción" },
    { value: "omarchy-capture-screenshot", label: "Captura de pantalla" },
    { value: "omarchy-capture-screenshot region", label: "Captura de región" },
    { value: "omarchy-capture-text", label: "Extraer texto (OCR)" },
    { value: "omarchy system lock", label: "Bloquear pantalla" },
    { value: "omarchy audio output volume raise", label: "Subir volumen" },
    { value: "omarchy audio output volume lower", label: "Bajar volumen" },
    { value: "omarchy audio output volume mute-toggle", label: "Silenciar" },
    { value: "omarchy brightness display +10%", label: "Subir brillo" },
    { value: "omarchy brightness display -10%", label: "Bajar brillo" },
    { value: "hyprctl dispatch workspace 1", label: "Ir al espacio 1" },
    { value: "hyprctl dispatch workspace 2", label: "Ir al espacio 2" },
    { value: "hyprctl dispatch workspace 3", label: "Ir al espacio 3" },
    { value: "hyprctl dispatch workspace 4", label: "Ir al espacio 4" },
    { value: "hyprctl dispatch workspace 5", label: "Ir al espacio 5" },
    { value: "alacritty", label: "Abrir terminal" },
    { value: "omarchy launch nautilus", label: "Abrir archivos" },
    { value: "omarchy launch browser", label: "Abrir navegador" },
    { value: "omarchy-shell shell toggle omarchy.emojis", label: "Selector de emojis" },
    { value: "omarchy-shell shell toggle omarchy.clipboard", label: "Portapapeles" },
    { value: "__custom__", label: "Comando personalizado…" }
  ]

  // ------------------------------------------------------------------ logic
  function knownCodes() {
    var out = []
    for (var i = 0; i < buttonDefs.length; i++) out.push(buttonDefs[i].code)
    return out
  }

  function isPressed(code) {
    return root.livePressed.indexOf(code) !== -1
  }

  function wasSeen(code) {
    return root.seenButtons.indexOf(code) !== -1
  }

  function handleEvent(evt) {
    var pressed = (evt && Array.isArray(evt.p)) ? evt.p : []
    root.livePressed = pressed
    var known = root.knownCodes()
    for (var i = 0; i < pressed.length; i++) {
      var c = pressed[i]
      if (root.seenButtons.indexOf(c) === -1)
        root.seenButtons = root.seenButtons.concat([c])
      if (known.indexOf(c) === -1) root.lastUnknown = "Botón no identificado: " + c
    }
    if (evt && evt.r !== null && evt.r !== undefined) {
      root.lastRel = evt.r
      wheelPulse.restart()
    }
  }

  function startEvents() {
    if (!root.device.connected || root.device.path === "") return
    eventsProc.command = ["python3", root.pluginDir + "/mxmouse-events.py", root.device.path]
    eventsProc.consumed = 0
    eventsProc.running = false
    eventsProc.running = true
  }

  function stopEvents() {
    eventsProc.running = false
    root.livePressed = []
  }

  function presetValues() {
    var out = []
    for (var i = 0; i < actions.length; i++) out.push(actions[i].value)
    return out
  }

  function commandFor(code) {
    var v = mappings[String(code)]
    return (typeof v === "string") ? v : ""
  }

  function isCustom(code) {
    var v = commandFor(code)
    if (v === "") return false
    var vals = presetValues()
    for (var i = 0; i < vals.length; i++) if (vals[i] === v) return false
    return true
  }

  // NOTE: QML only re-evaluates bindings when a property is REASSIGNED —
  // mutating the object in place emits no change notification. Every state
  // change below therefore builds a fresh object and reassigns it.
  function initSelection() {
    var s = {}
    var t = {}
    for (var i = 0; i < buttonDefs.length; i++) {
      var c = String(buttonDefs[i].code)
      var custom = isCustom(buttonDefs[i].code)
      s[c] = custom ? "__custom__" : commandFor(buttonDefs[i].code)
      t[c] = custom ? commandFor(buttonDefs[i].code) : ""
    }
    root.selection = s
    root.customText = t
  }

  function setAction(code, value) {
    var s = {}
    for (var k in selection) s[k] = selection[k]
    s[String(code)] = value
    root.selection = s
    if (value === "__custom__") return
    var m = {}
    for (var k in mappings) m[k] = mappings[k]
    if (value === "") delete m[String(code)]
    else m[String(code)] = value
    root.mappings = m
    root.scheduleApply()
  }

  function setCustom(code, text) {
    var t = {}
    for (var k in customText) t[k] = customText[k]
    t[String(code)] = text
    root.customText = t
    var m = {}
    for (var k in mappings) m[k] = mappings[k]
    if (text !== "") m[String(code)] = text
    else delete m[String(code)]
    root.mappings = m
    root.scheduleApply()
  }

  // Auto-apply: changes take effect as soon as the user stops fiddling.
  function scheduleApply() {
    applyTimer.restart()
  }

  function luaEscape(s) {
    return String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"')
  }

  // execDetached drops extra argv elements in this Quickshell build, so the
  // file content is base64-embedded into a self-contained bash script.
  function base64Encode(str) {
    var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    var bytes = []
    for (var i = 0; i < str.length; i++) {
      var c = str.charCodeAt(i)
      if (c < 0x80) {
        bytes.push(c)
      } else if (c < 0x800) {
        bytes.push(0xC0 | (c >> 6), 0x80 | (c & 0x3F))
      } else if (c >= 0xD800 && c < 0xDC00 && i + 1 < str.length) {
        var c2 = str.charCodeAt(++i)
        var cp = 0x10000 + ((c - 0xD800) << 10) + (c2 - 0xDC00)
        bytes.push(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F))
      } else {
        bytes.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 0x3F), 0x80 | (c & 0x3F))
      }
    }
    var out = ""
    for (var j = 0; j < bytes.length; j += 3) {
      var b1 = bytes[j], b2 = j + 1 < bytes.length ? bytes[j + 1] : 0, b3 = j + 2 < bytes.length ? bytes[j + 2] : 0
      out += chars[b1 >> 2]
      out += chars[((b1 & 3) << 4) | (b2 >> 4)]
      out += j + 1 < bytes.length ? chars[((b2 & 15) << 2) | (b3 >> 6)] : "="
      out += j + 2 < bytes.length ? chars[b3 & 63] : "="
    }
    return out
  }

  function writeFile(path, content) {
    Quickshell.execDetached(["bash", "-c", "echo " + root.base64Encode(content) + " | base64 -d > " + path])
  }

  function buildLua() {
    var lines = [
      "-- MX Master 3 · mapeo de botones",
      "-- Generado por amartin.mouse-mapper (overlay Mouse Mapper).",
      "-- Cambia las acciones desde el overlay; se regenera este archivo.",
      ""
    ]
    for (var i = 0; i < buttonDefs.length; i++) {
      var b = buttonDefs[i]
      var cmd = commandFor(b.code)
      if (cmd === "") continue
      lines.push('o.bind("mouse:' + b.code + '", "MX Master 3 · ' + b.name + '", "' + luaEscape(cmd) + '")')
    }
    if (lines.length === 4) lines.push("-- (sin acciones asignadas)")
    return lines.join("\n") + "\n"
  }

  // Read the state file fresh on every open. A FileView configured at
  // plugin load never sees a state file created afterwards, so the
  // previous version could reload an empty mapping.
  function loadMappings() {
    loadProc.command = ["bash", "-c", "cat " + root.stateFile + " 2>/dev/null"]
    loadProc.running = false
    loadProc.running = true
  }

  function refreshDevice() {
    deviceProc.command = ["bash", root.pluginDir + "/mxmouse-info.sh"]
    deviceProc.running = false
    deviceProc.running = true
  }

  function apply() {
    if (root.applying) return
    root.applying = true
    root.status = "Guardando…"
    root.writeFile(root.stateFile, JSON.stringify(root.mappings))
    root.writeFile(root.mouseLua, root.buildLua())
    reloadProc.running = false
    reloadProc.running = true
  }

  // How many of the known buttons have been pressed since the overlay opened.
  function testedCount() {
    var known = root.knownCodes()
    var n = 0
    for (var i = 0; i < known.length; i++)
      if (root.seenButtons.indexOf(known[i]) !== -1) n++
    return n
  }

  // ------------------------------------------------------------------ shell
  function open(payloadJson) {
    root.opened = true
    root.status = ""
    root.lastUnknown = ""
    root.seenButtons = []
    root.livePressed = []
    root.loadMappings()
    root.refreshDevice()
    window.visible = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.closingFromHost = true
    root.opened = false
    root.stopEvents()
    window.visible = false
    root.closingFromHost = false
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "amartin.mouse-mapper")
    else
      root.close()
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // ------------------------------------------------------------------ io
  // On-demand state-file reader (see loadMappings).
  Process {
    id: loadProc
    running: false
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var m = {}
        try { m = JSON.parse(text.trim()) } catch (e) { m = {} }
        root.mappings = m
        root.initSelection()
      }
    }
  }

  Process {
    id: deviceProc
    running: false
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(text.trim())
          root.device = d
          if (d.connected) root.startEvents()
          else root.stopEvents()
        } catch (e) {
          console.warn("mouse-mapper: bad device info:", e)
        }
      }
    }
  }

  // Live evdev reader: emits a full state snapshot per event.
  Process {
    id: eventsProc
    running: false
    command: []
    property int consumed: 0
    onExited: root.stopEvents()
    stdout: StdioCollector {
      waitForEnd: false
      onTextChanged: {
        // `text` is cumulative; parse only the newly completed lines.
        if (text.length < eventsProc.consumed) eventsProc.consumed = 0
        var end = text.lastIndexOf("\n")
        if (end < eventsProc.consumed) return
        var chunk = text.slice(eventsProc.consumed, end)
        eventsProc.consumed = end + 1
        var lines = chunk.split("\n")
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i].trim()
          if (line === "") continue
          try { root.handleEvent(JSON.parse(line)) } catch (e) {}
        }
      }
    }
  }

  Timer {
    id: wheelPulse
    interval: 400
    repeat: false
    onTriggered: root.lastRel = -1
  }

  // Debounced auto-apply.
  Timer {
    id: applyTimer
    interval: 400
    repeat: false
    onTriggered: root.apply()
  }

  Process {
    id: reloadProc
    running: false
    command: ["hyprctl", "reload"]
    onExited: function(code) {
      root.applying = false
      root.status = code === 0 ? "Guardado" : "Error al recargar Hyprland"
    }
  }

  // ------------------------------------------------------------------ ui
  // A normal window: Hyprland (via the active theme's hyprbars) draws the
  // title bar and traffic-light buttons, so this reads like any other app.
  FloatingWindow {
    id: window
    title: "Mouse Mapper"
    visible: false
    color: root.windowBackground
    implicitWidth: 620
    implicitHeight: 680
    minimumSize: Qt.size(540, 420)

    onVisibleChanged: {
      // The red close button hides the window without going through
      // close(); tell the shell so its open state stays consistent.
      if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function")
        root.shell.hide((root.manifest && root.manifest.id) || "amartin.mouse-mapper")
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.dismiss()
          event.accepted = true
        }
      }
    }

    ScrollView {
      id: scrollArea
      anchors.fill: parent
      anchors.margins: root.contentMargin
      clip: true
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

      Column {
        id: contentColumn
        width: root.contentWidth
        spacing: Style.space(14)

        // ------------------------------------------------ hero
        Row {
          spacing: Style.space(18)

          // Wrapper keeps the layout footprint honest: Item.scale alone
          // would leave the layout box unscaled and overlap the rail below.
          Item {
            width: 47
            height: 72
            anchors.verticalCenter: parent.verticalCenter

            MouseGlyph {
              button: -1
              anchors.centerIn: parent
              scale: 1.8
            }
          }

          Column {
            spacing: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter

            Text {
              text: "MX Master 3"
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              font.bold: true
              color: root.foreground
            }
            Text {
              text: (root.device.connected
                ? "Logitech · Bluetooth · " + root.device.path
                : "Logitech · Bluetooth").toUpperCase()
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.letterSpacing: 1
              color: Qt.darker(root.foreground, 1.5)
            }
          }

          Item { width: 1; height: 1 }

          // Small-caps status, clock-label style.
          Row {
            spacing: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
              width: 8
              height: 8
              radius: 4
              anchors.verticalCenter: parent.verticalCenter
              color: root.device.connected
                ? Style.selectedStateColor(root.foreground, Color.accent)
                : Color.urgent
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.device.connected ? "CONECTADO" : "NO DETECTADO"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.letterSpacing: 1
              color: Qt.darker(root.foreground, 1.5)
            }
          }
        }

        // ------------------------------------------------ test rail (clock progress pattern)
        Item {
          width: parent.width
          height: Style.space(10)

          Text {
            id: testLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "PRUEBA"
            color: Qt.darker(root.foreground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.letterSpacing: 1
          }

          Text {
            id: testCount
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.testedCount() + "/" + root.buttonDefs.length
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Rectangle {
            anchors.left: testLabel.right
            anchors.right: testCount.left
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(6)
            radius: Style.cornerRadius > 0 ? height / 2 : 0
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

            Rectangle {
              width: Math.round(parent.width * (root.testedCount() / root.buttonDefs.length))
              height: parent.height
              radius: parent.radius
              color: Style.selectedStateColor(root.foreground, Color.accent)
              Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }
          }
        }

        Text {
          text: "Pulsa los botones del ratón: su fila se ilumina en vivo."
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          color: Qt.darker(root.foreground, 1.9)
        }

        // ------------------------------------------------ buttons section
        Text {
          text: "BOTONES"
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.letterSpacing: 1
        }

        // Rows are recreated on every open: once the user picks an option,
        // the Dropdown's `value` binding is destroyed (its selectCurrent
        // assigns the property directly), so a persistent delegate would
        // keep showing the stale value from the previous session.
        Repeater {
          model: root.opened ? root.buttonDefs : []

          delegate: Column {
            width: root.contentWidth
            spacing: Style.space(3)

            Rectangle {
              width: root.contentWidth
              height: Style.space(44)
              radius: Style.cornerRadius
              color: root.isPressed(modelData.code)
                ? Util.alpha(Color.accent, 0.18)
                : rowHover.hovered
                  ? Style.hoverFillFor(root.foreground, Color.accent)
                  : "transparent"
              Behavior on color { ColorAnimation { duration: 120 } }

              MouseArea {
                id: rowHover
                anchors.fill: parent
                hoverEnabled: true
              }

              Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Style.space(14)
                anchors.rightMargin: Style.space(14)
                spacing: Style.space(12)

                MouseGlyph {
                  button: modelData.code
                  anchors.verticalCenter: parent.verticalCenter
                }

                // Fixed-width name column so every dropdown left-aligns.
                Column {
                  width: Style.space(140)
                  spacing: 1
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    text: modelData.name
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    color: root.isPressed(modelData.code)
                      ? Style.selectedStateColor(root.foreground, Color.accent)
                      : root.foreground
                  }
                  Text {
                    text: modelData.hint
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    color: Qt.darker(root.foreground, 1.5)
                  }
                }

                Dropdown {
                  width: Style.spacing.dropdownWidth
                  showLabel: false
                  options: root.actions
                  value: root.selection[String(modelData.code)] || ""
                  onValueChanged: root.setAction(modelData.code, value)
                }

                Item { width: 1; height: 1; anchors.verticalCenter: parent.verticalCenter }

                // Fixed slot so the check never shifts the layout.
                Item {
                  width: Style.space(16)
                  height: 1
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    anchors.centerIn: parent
                    text: "✓"
                    visible: root.wasSeen(modelData.code)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    color: Style.selectedStateColor(root.foreground, Color.accent)
                  }
                }
              }
            }

            TextField {
              visible: (root.selection[String(modelData.code)] || "") === "__custom__"
              // Aligned under the dropdown: margin + glyph + gaps + name column.
              x: Style.space(14) + 26 + Style.space(12) + Style.space(140) + Style.space(12)
              width: root.contentWidth - x - Style.space(14)
              placeholderText: "comando a ejecutar…"
              text: root.customText[String(modelData.code)] || ""
              onTextChanged: root.setCustom(modelData.code, text)
            }
          }
        }

        // ------------------------------------------------ wheel section
        Text {
          text: "RUEDA"
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.letterSpacing: 1
        }

        Rectangle {
          width: root.contentWidth
          height: Style.space(44)
          radius: Style.cornerRadius
          color: root.lastRel >= 0 ? Util.alpha(Color.accent, 0.10) : "transparent"
          Behavior on color { ColorAnimation { duration: 150 } }

          Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(14)
            anchors.rightMargin: Style.space(14)
            spacing: Style.space(12)

            MouseGlyph {
              button: 274
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              spacing: 1
              anchors.verticalCenter: parent.verticalCenter

              Text {
                text: "Rueda"
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                color: root.foreground
              }
              Text {
                text: "Scroll vertical · Smart Shift (horizontal)"
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                color: Qt.darker(root.foreground, 1.5)
              }
            }

            Item { width: 1; height: 1; anchors.verticalCenter: parent.verticalCenter }

            Row {
              spacing: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter

              Rectangle {
                width: 8
                height: 8
                radius: 4
                anchors.verticalCenter: parent.verticalCenter
                color: root.lastRel >= 0
                  ? Style.selectedStateColor(root.foreground, Color.accent)
                  : Qt.darker(root.foreground, 1.9)
                Behavior on color { ColorAnimation { duration: 150 } }
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.lastRel >= 0 ? "ACTIVIDAD" : "EN REPOSO"
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
                color: root.lastRel >= 0
                  ? Style.selectedStateColor(root.foreground, Color.accent)
                  : Qt.darker(root.foreground, 1.5)
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "NO MAPEABLE"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.letterSpacing: 1
              color: Qt.darker(root.foreground, 1.9)
            }
          }
        }

        // ------------------------------------------------ footer
        Rectangle {
          width: parent.width
          height: 1
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
        }

        Row {
          spacing: Style.spacing.md

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: (root.lastUnknown !== "" ? root.lastUnknown : root.status).toUpperCase()
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.letterSpacing: 1
            color: root.lastUnknown !== "" ? Color.urgent
                 : (root.status === "Error al recargar Hyprland" ? Color.urgent
                    : Style.selectedStateColor(root.foreground, Color.accent))
          }

          Item { width: 1; height: 1 }

          Button {
            text: "Cerrar"
            bordered: true
            anchors.verticalCenter: parent.verticalCenter
            onClicked: root.dismiss()
          }
        }
      }
    }
  }
}
