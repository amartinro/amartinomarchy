import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Item {
  id: root
  property var bar
  property string moduleName
  property var settings

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property real barSize: bar ? bar.barSize : 26

  property real cpuPercent: 0
  property real memPercent: 0
  property real memUsedGiB: 0
  property real memTotalGiB: 0
  property real netRxPerSec: 0
  property real netTxPerSec: 0
  property int cpuCoreCount: 0
  property bool sampled: false

  property var lastSample: null

  function openBtop() {
    if (root.bar) root.bar.run("omarchy-launch-or-focus-tui btop")
  }

  function openTerminal() {
    if (root.bar) root.bar.run("omarchy-launch-terminal")
  }

  function refreshNow() {
    if (!sampleProc.running) sampleProc.running = true
  }

  function triggerPress(button) {
    if (button === Qt.RightButton) openTerminal()
    else if (button === Qt.MiddleButton) refreshNow()
    else openBtop()
  }

  function humanize(bytes) {
    var units = ["B", "KiB", "MiB", "GiB", "TiB"]
    var v = Number(bytes) || 0
    var u = 0
    while (v >= 1024 && u < units.length - 1) {
      v = v / 1024
      u++
    }
    var s = (u === 0 || v >= 10) ? String(Math.round(v)) : String(Number(v.toFixed(1)))
    return s + " " + units[u]
  }

  function compactRate(bytesPerSec) {
    var v = Number(bytesPerSec) || 0
    if (v >= 1073741824) return String(Number((v / 1073741824).toFixed(1))) + "G"
    if (v >= 1048576) return String(Number((v / 1048576).toFixed(1))) + "M"
    if (v >= 1024) return String(Math.round(v / 1024)) + "K"
    return String(Math.round(v))
  }

  readonly property string cpuLabel: sampled ? Math.round(cpuPercent) + "%" : "--"
  readonly property string memLabel: memTotalGiB > 0 ? memUsedGiB.toFixed(1) + "G" : "--"
  readonly property string netLabel: "\uF063" + " " + (sampled ? compactRate(netRxPerSec) : "--")
    + "  " + "\uF062" + " " + (sampled ? compactRate(netTxPerSec) : "--")

  readonly property string cpuTooltip: "CPU " + cpuLabel + (cpuCoreCount > 0 ? " · " + cpuCoreCount + " cores" : "")
  readonly property string memTooltip: memTotalGiB > 0
    ? "RAM " + memUsedGiB.toFixed(1) + " / " + memTotalGiB.toFixed(1) + " GiB (" + Math.round(memPercent) + "%)"
    : "RAM"
  readonly property string netTooltip: "Net \u2193" + humanize(netRxPerSec) + "/s \u00B7 \u2191" + humanize(netTxPerSec) + "/s"

  Process {
    id: sampleProc
    command: ["bash", "-lc", "cat /proc/stat /proc/meminfo /proc/net/dev"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.sample(text)
    }
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshNow()
  }

  function sample(raw) {
    var lines = String(raw || "").split("\n")
    var cpuTotal = 0
    var cpuIdle = 0
    var cores = 0
    var memTotalKb = 0
    var memAvailKb = 0
    var rxBytes = 0
    var txBytes = 0
    var inNet = false
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (line.length === 0) continue
      if (i === 0 && line.substring(0, 3) === "cpu") {
        var f = line.trim().split(/\s+/)
        for (var j = 1; j <= 8 && j < f.length; j++) {
          var v = Number(f[j])
          if (!isFinite(v)) break
          cpuTotal += v
          if (j === 4 || j === 5) cpuIdle += v
        }
        continue
      }
      if (/^cpu\d+ /.test(line)) {
        cores++
        continue
      }
      if (line.indexOf("MemTotal:") === 0) {
        memTotalKb = Number(line.split(/\s+/)[1])
        continue
      }
      if (line.indexOf("MemAvailable:") === 0) {
        memAvailKb = Number(line.split(/\s+/)[1])
        continue
      }
      if (line.indexOf("Inter-|") === 0) {
        inNet = true
        continue
      }
      if (inNet) {
        if (line.indexOf("|") >= 0) continue
        var colon = line.indexOf(":")
        if (colon < 0) continue
        var iface = line.substring(0, colon).trim()
        var nums = line.substring(colon + 1).trim().split(/\s+/)
        if (iface !== "lo" && nums.length >= 9) {
          rxBytes += Number(nums[0])
          txBytes += Number(nums[8])
        }
      }
    }

    var now = Date.now()
    var prev = root.lastSample
    if (cpuTotal > 0 && prev && prev.cpuTotal > 0 && cpuTotal >= prev.cpuTotal
        && cpuIdle >= prev.cpuIdle) {
      var dTotal = cpuTotal - prev.cpuTotal
      var dIdle = cpuIdle - prev.cpuIdle
      if (dTotal > 0) {
        var pct = 100 * (1 - dIdle / dTotal)
        root.cpuPercent = Math.max(0, Math.min(100, pct))
      }
    }
    if (memTotalKb > 0) {
      root.memTotalGiB = memTotalKb / 1048576
      root.memUsedGiB = Math.max(0, memTotalKb - memAvailKb) / 1048576
      root.memPercent = Math.max(0, Math.min(100, 100 * (1 - memAvailKb / memTotalKb)))
    }
    if (prev) {
      var dt = (now - prev.time) / 1000
      if (dt > 0.2) {
        var instRx = Math.max(0, rxBytes - prev.rx) / dt
        var instTx = Math.max(0, txBytes - prev.tx) / dt
        root.netRxPerSec = 0.65 * root.netRxPerSec + 0.35 * instRx
        root.netTxPerSec = 0.65 * root.netTxPerSec + 0.35 * instTx
      }
    }
    if (cores > 0) root.cpuCoreCount = cores
    root.sampled = true
    root.lastSample = {
      cpuTotal: cpuTotal,
      cpuIdle: cpuIdle,
      rx: rxBytes,
      tx: txBytes,
      time: now
    }
  }

  component MonitorChip: WidgetButton {
    id: chip
    property string chipIcon: ""
    property string chipVerticalIcon: ""
    property string chipValue: ""
    property string chipTooltip: ""
    property bool alarming: false

    bar: root.bar
    text: root.vertical ? (chipVerticalIcon !== "" ? chipVerticalIcon : chipIcon)
      : chipIcon + (chipValue !== "" ? " " + chipValue : "")
    tooltipText: chipTooltip
    active: alarming
    horizontalMargin: 6
    onPressed: function(button) {
      if (button === Qt.RightButton) root.openTerminal()
      else if (button === Qt.MiddleButton) root.refreshNow()
      else root.openBtop()
    }
  }

  Row {
    id: hRow
    visible: !root.vertical
    anchors.verticalCenter: parent.verticalCenter
    spacing: 0

    MonitorChip {
      chipIcon: "\uF4BC"
      chipValue: root.cpuLabel
      chipTooltip: root.cpuTooltip
      alarming: root.cpuPercent >= 85
    }

    MonitorChip {
      chipIcon: "\uDB80\uDF5B"
      chipValue: root.memLabel
      chipTooltip: root.memTooltip
      alarming: root.memPercent >= 90
    }

    MonitorChip {
      chipIcon: ""
      chipValue: root.netLabel
      chipTooltip: root.netTooltip
    }
  }

  Column {
    id: vColumn
    visible: root.vertical
    spacing: 0

    MonitorChip {
      chipIcon: "\uF4BC"
      chipTooltip: root.cpuTooltip
      alarming: root.cpuPercent >= 85
    }

    MonitorChip {
      chipIcon: "\uDB80\uDF5B"
      chipTooltip: root.memTooltip
      alarming: root.memPercent >= 90
    }

    MonitorChip {
      chipIcon: "\uF063"
      chipVerticalIcon: "\uEF44"
      chipTooltip: root.netTooltip
    }
  }

  implicitWidth: root.vertical ? root.barSize : hRow.implicitWidth
  implicitHeight: root.vertical ? vColumn.implicitHeight : hRow.implicitHeight
}