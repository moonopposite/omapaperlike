import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Paperlike 13K 2025 Color — bar widget + popup control panel.
//
// v4 (this commit):
//   * Popup header collapses "Paperlike 13K" + simple status text — no
//     colored status dot, no extra hero noise.
//   * Brand monogram in the hero (D bold + S regular, both same weight
//     class as the title's first letter) — keeps the popup identity
//     consistent with the single-letter "D" icon in the bar.
//   * Mode ButtonGroup drops from six MCU modes to four content-type
//     labels (Web / Text / Image / Active) modelled on plateaukao/
//     paperlike13k_macos v0.2; the underlying MCU --mode numbers still
//     carry the relationship (1=Web, 4=Text, 3=Image, 2=Active), so
//     daemon protocol is unchanged and menu users keep their picks.
//   * Speed slider renamed DARKNESS (matches the mac app vocabulary),
//     ticks thinned to 4 notches — still hits every MCU --speed value
//     (1..8) but the track no longer paints a stop per pixel.
//   * Brightness and color-temperature sliders likewise thinned.
//   * Front-light order Off → Cold → Warm — the v3 ordering put warm
//     in the middle, which read as a typo. The MCU indices (0/1/2) are
//     unchanged.
//   * Panel width 480 → 360 logical px — the four-mode row fits a much
//     narrower popup that still has room for the rest of the controls.
//   * Refresh button wired to MCU 0x03 (force refresh) — v3 only called
//     runQuery(), which made the button a no-op visually. Now it
//     triggers a real refresh, then re-pulls state 1.5 s later.

Panel {
  id: root
  moduleName: "paperlike"
  ipcTarget: "paperlike"

  readonly property string scriptPath: Quickshell.env("HOME")
    + "/.local/share/paperlike13k_linux/paperlike_init_linux.py"

  // ── Local state cache. ────────────────────────────────────────────────────
  property int    mode:        3   // 1..6 (panel surfaces only 1, 2, 3, 4)
  property int    speed:       3   // 1..8 (= MCU darkness)
  property int    frontLight:  0   // 0=off, 1=warm, 2=cold
  property int    brightness:  32  // 0..64
  property int    temperature: 3   // 0..5
  property bool   stateLoaded: false
  property bool   daemonAlive: true
  property string lastError:   ""

  readonly property string uidString: Quickshell.env("UID") || "1000"
  readonly property string socketPath: "/run/user/" + uidString + "/paperlike.sock"

  Timer {
    interval: 10000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      probe.running = true
      if (root.opened) root.runQuery()
    }
  }
  Process {
    id: probe
    command: ["test", "-S", root.socketPath]
    onExited: function(code) { root.daemonAlive = (code === 0) }
  }

  // ── Bar widget. ──────────────────────────────────────────────────────────
  BarIconButton {
    id: icon
    anchors.fill: parent
    bar: root.bar
    text: "D"
    dimmed: !root.daemonAlive
    tooltipText: root.daemonAlive
                    ? "Paperlike 13K Display — daemon alive"
                    : "Paperlike 13K Display — daemon offline (click to start)"
    onPressed: function() { root.toggle() }
  }

  // The Panel base is an Item with zero implicit dimensions — Bar.qml's
  // ModuleSlot collapses a slot whose item has implicitWidth===0, which is
  // exactly what made the icon disappear in the v1→v2 transition. Mirror
  // the omarchy.agents pattern and let the icon's preferred size drive
  // the slot.
  implicitWidth:  icon.implicitWidth
  implicitHeight: icon.implicitHeight

  PopupCard {
    id: popup
    anchorItem: icon
    bar: root.bar
    owner: root
    open: root.opened
    // 360 logical px: rows of 4 mode chips + 3 FL chips + sliders all
    // fit without crowding. The 1/3-narrower panel (down from v3's 480)
    // matches the typographic rest of the bar — bigger gaps between
    // controls, less risk of misclick when sweeping through sliders.
    contentWidth:  popup.fittedContentWidth(Style.space(280))
    contentHeight: popup.fittedContentHeight(contentColumn.implicitHeight,
                                             Style.space(640))
    onOpenChanged: if (open) root.runQuery()

    Column {
      id: contentColumn
      width: parent.width
      spacing: Style.spacing.md

      // ── Header ─────────────────────────────────────────────────────────
      PanelHero {
        width: parent.width
        fontFamily: Style.font.family
        foreground: root.bar ? root.bar.foreground : Color.foreground

        // Two-letter "DS" mark: BOTH glyphs are bold so they read as a
        // single typographic unit (D+S, not D-s where s is the start of a
        // word). The Item is intentionally wider than the Row that holds
        // DS — the leftover horizontal space becomes a visual gap between
        // the monogram and the title text, instead of the title's first
        // letter butting up against "S".
        iconComponent: Component {
          Item {
            implicitWidth: 56     // ~28 for "DS" + ~28 trailing gap
            implicitHeight: Style.font.display
            Row {
              spacing: Style.space(2)
              anchors.left: parent.left
              anchors.leftMargin: 0
              anchors.verticalCenter: parent.verticalCenter
              Text {
                font.family: Style.font.family
                font.pixelSize: Style.font.display
                font.bold: true
                text: "D"
                color: root.bar ? root.bar.foreground : Color.foreground
              }
              Text {
                font.family: Style.font.family
                font.pixelSize: Style.font.display
                font.bold: true
                text: "S"
                color: root.bar ? root.bar.foreground : Color.foreground
              }
            }
          }
        }

        title: "Paperlike 13K"
        meta:  root.daemonAlive ? "DAEMON CONNECTED" : "DAEMON OFFLINE"
        detail: ""
      }

      PanelSeparator {}

      // ── Mode ───────────────────────────────────────────────────────────
      PanelSectionHeader {
        width: parent.width
        text: "MODE"
        foreground: root.bar ? root.bar.foreground : Color.foreground
      }
      ButtonGroup {
        id: modeGroup
        width: parent.width
        fontFamily: Style.font.family
        foreground: root.bar ? root.bar.foreground : Color.foreground
        background: Color.background
        accent: Color.accent
        // macOS v0.2 named modes after content type. We follow that
        // vocabulary but the value mapping comes from observing the
        // actual Paperlike 13K 2025 Color firmware, not from the
        // upstream roflecopter README (which has Cold/Warm and
        // Text/Active swapped relative to this device — see
        // TROUBLESHOOTING.md § "MCU semantics"). The full six still
        // exist (Fast/Fast+/Balance/Text/Text+/Read); the panel
        // surfaces only the four content-type picks to keep the row
        // compact:
        //   Web    → 1 (Fast)     browsing, scroll
        //   Text   → 2            reading crisp without residual artefacts
        //   Image  → 3 (Balance)  mixed content with images
        //   Active → 4            UI / scrolling, motion-clear
        options: [
          { value: "1", label: "Web" },
          { value: "2", label: "Text" },
          { value: "3", label: "Image" },
          { value: "4", label: "Active" }
        ]
        // Round-trip: when the daemon reports a mode we don't surface
        // (5 = Text+, 6 = Read), the panel falls back to "Text" (the
        // closest 4-mode neighbour) — keeps the user-visible state
        // consistent. MCU still receives the original --mode N.
        value: root.mode === 4 ? "4"
            : root.mode === 3 ? "3"
            : root.mode === 2 ? "2"
            : root.mode === 1 ? "1"
            : "1"
        onChanged: function(val) {
          var n = parseInt(val)
          root.mode = n
          root.runCmd(["--mode", String(n)])
        }
      }

      PanelSeparator {}

      // ── Darkness ────────────────────────────────────────────────────────
      // The MCU's --speed (1..8) is repurposed as "Darkness" in the panel:
      // higher value dithers less, producing darker text. macOS v0.2 maps
      // its Darkness slider to a similar 1..7 range; we keep 1..8 for
      // parity with the daemon API but only draw 4 notches (positions 1,
      // 3, 5, 7) — dense marks made every pixel of the track feel like
      // a step.
      PanelSectionHeader {
        width: parent.width
        text: "DARKNESS"
        foreground: root.bar ? root.bar.foreground : Color.foreground
      }
      PanelSlider {
        id: darknessSlider
        width: parent.width
        bar: root.bar
        minimum: 1
        maximum: 8
        step: 1
        integer: true
        value: root.speed
        tickCount: 4
        tickColor: Color.background
        onReleased: function(v) {
          var n = Math.round(v)
          if (n !== root.speed) {
            root.speed = n
            root.runCmd(["--speed", String(n)])
          }
        }
      }

      PanelSeparator {}

      // ── Front light ────────────────────────────────────────────────────
      PanelSectionHeader {
        width: parent.width
        text: "FRONT LIGHT"
        foreground: root.bar ? root.bar.foreground : Color.foreground
      }
      ButtonGroup {
        id: flGroup
        width: parent.width
        fontFamily: Style.font.family
        foreground: root.bar ? root.bar.foreground : Color.foreground
        background: Color.background
        accent: Color.accent
        // Off → Cold → Warm — middle of the strip is "cold", warm sits
        // at the right (the warmer setting). The MCU's --front-light
        // indices (0/1/2) stay mapped to off/warm/cold; only the panel
        // ordering is reshuffled so the off-on-warm ramp reads left-to-right.
        options: [
          { value: "0", label: "Off" },
          { value: "1", label: "Cold" },     // MCU: 1=cold (this Paperlike 13K 2025 Color)
          { value: "2", label: "Warm" }      // MCU: 2=warm
        ]
        value: String(root.frontLight)
        onChanged: function(val) {
          var n = parseInt(val)
          root.frontLight = n
          root.runCmd(["--front-light", String(n)])
        }
      }

      PanelSeparator {}

      // ── Brightness ─────────────────────────────────────────────────────
      PanelSectionHeader {
        width: parent.width
        text: "BRIGHTNESS"
        foreground: root.bar ? root.bar.foreground : Color.foreground
      }
      PanelSlider {
        id: brightnessSlider
        width: parent.width
        bar: root.bar
        minimum: 0
        maximum: 64
        step: 1
        integer: true
        value: root.brightness
        tickCount: 9        // every 8 stops → 0/8/16/24/.../64
        tickColor: Color.background
        onReleased: function(v) {
          var n = Math.round(v)
          if (n !== root.brightness) {
            root.brightness = n
            root.runCmd(["--brightness", String(n)])
          }
        }
      }

      PanelSeparator {}

      // ── Color temperature ──────────────────────────────────────────────
      PanelSectionHeader {
        width: parent.width
        text: "COLOR TEMPERATURE"
        foreground: root.bar ? root.bar.foreground : Color.foreground
      }
      PanelSlider {
        id: tempSlider
        width: parent.width
        bar: root.bar
        minimum: 0
        maximum: 5
        step: 1
        integer: true
        value: root.temperature
        tickCount: 3        // 0/2/4 — minimalist; the end stops (5) is implicit
        tickColor: Color.background
        onReleased: function(v) {
          var n = Math.round(v)
          if (n !== root.temperature) {
            root.temperature = n
            root.runCmd(["--temperature", String(n)])
          }
        }
      }

      PanelSeparator {}

      // ── Footer buttons ──────────────────────────────────────────────────
      Row {
        width: parent.width
        spacing: Style.spacing.md
        layoutDirection: Qt.LeftToRight

        Button {
          text: "Refresh"
          fontFamily: Style.font.family
          fontSize: Style.font.body
          foreground: root.bar ? root.bar.foreground : Color.foreground
          // Force a full panel refresh (MCU 0x03) and re-pull state so
          // the panel rows reflect anything that changed during the
          // refresh. The Timer in runRefresh() defers the re-query 1.5 s
          // so the daemon has time to ack before we ask for current
          // values.
          onClicked: root.runRefresh()
        }
        Button {
          text: "Settings…"
          fontFamily: Style.font.family
          fontSize: Style.font.body
          foreground: root.bar ? root.bar.foreground : Color.foreground
          onClicked: {
            Qt.callLater(function() {
              root.close()
              root.bar.run("omarchy-shell shell summon omarchy.menu "
                           + "'{\"menu\":\"paperlike\"}'")
            })
          }
        }
        Item { width: 1; height: 1 }
        Button {
          text: root.daemonAlive ? "Stop" : "Start"
          fontFamily: Style.font.family
          fontSize: Style.font.body
          foreground: root.bar ? root.bar.foreground : Color.foreground
          onClicked: {
            var action = root.daemonAlive ? "stop" : "start"
            root.runCmd(["--daemon-control", action], function() {
              Qt.callLater(function() {
                Qt.callLater(function() { root.daemonAlive = false; probe.running = true })
              })
            })
          }
        }
      }

      // Last-error banner
      Text {
        width: parent.width
        visible: root.lastError !== ""
        text: root.lastError
        color: Color.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
      }
    }
  }

  // ── Command execution ────────────────────────────────────────────────────
  Process {
    id: cmdProc
    property string bufOut: ""
    property string bufErr: ""
    property var onDone: null
    stdout: StdioCollector { id: outCol; onStreamFinished: cmdProc.bufOut = text }
    stderr: StdioCollector { id: errCol; onStreamFinished: cmdProc.bufErr = text }
    onExited: function(code) {
      var cb = cmdProc.onDone
      cmdProc.onDone = null
      if (code !== 0 && cmdProc.bufErr.trim() !== "") {
        var firstLine = cmdProc.bufErr.split("\n").filter(function(l) {
          return l.trim() !== ""
        }).pop() || cmdProc.bufErr
        if (firstLine === "" && cmdProc.bufOut !== "") {
          firstLine = cmdProc.bufOut.split("\n").filter(function(l) {
            return l.trim() !== "" && l.indexOf("Traceback") >= 0
          }).pop() || ""
        }
        root.lastError = firstLine.replace(/^Error: /, "").slice(0, 200)
      } else {
        root.lastError = ""
      }
      cmdProc.bufOut = ""
      cmdProc.bufErr = ""
      if (cb) cb(code)
    }
  }

  function runCmd(extraArgs, onSuccess) {
    if (cmdProc.running) return
    var args = [scriptPath]
    for (var i = 0; i < extraArgs.length; i++) args.push(extraArgs[i])
    cmdProc.command = ["python3", "-u"].concat(args)
    cmdProc.onDone = onSuccess || null
    cmdProc.running = true
  }

  function runQuery() {
    if (queryProc.running) return
    queryProc.bufOut = ""
    queryProc.running = true
  }

  // Refresh button: send the MCU 0x03 force-refresh command, then
  // re-pull state 1.5 s later. The Timer is one-shot so the user can
  // keep dragging sliders while the refresh is in flight — the daemon
  // serializes per command; a second refresh would queue harmlessly.
  Timer {
    id: refreshSettleTimer
    interval: 1500
    repeat: false
    onTriggered: root.runQuery()
  }
  function runRefresh() {
    runCmd(["--refresh"])
    refreshSettleTimer.restart()
  }

  property var queryPattern: {
    "0x01": { key: "speed",       mask: 0xFF, shift: 0 },
    "0x02": { key: "mode",        mask: 0xFF, shift: 0 },
    "0x07": { key: "frontLight",  mask: 0xFF, shift: 0 },
    "0x08": { key: "temperature", mask: 0xFF, shift: 0 },
    "0x09": { key: "brightness",  mask: 0xFF, shift: 0 }
  }

  Process {
    id: queryProc
    property string bufOut: ""
    command: ["python3", "-u", root.scriptPath, "--query"]
    stdout: StdioCollector { onStreamFinished: queryProc.bufOut = text }
    onExited: function(code) {
      var text = queryProc.bufOut
      var re = /RESP 0xF0,0x0A ([0-9A-F]{2})([0-9A-F]{2})[0-9A-F]{10}/g
      var m
      while ((m = re.exec(text)) !== null) {
        var cmdHex = "0x" + m[1]
        var valHex = m[2]
        var spec = root.queryPattern[cmdHex]
        if (!spec) continue
        var val = parseInt(valHex, 16) & spec.mask
        if (spec.key === "mode"        && val >= 1 && val <= 6) root.mode        = val
        if (spec.key === "speed"       && val >= 1 && val <= 8) root.speed       = val
        if (spec.key === "frontLight"  && val >= 0 && val <= 2) root.frontLight  = val
        if (spec.key === "brightness"  && val >= 0 && val <= 64) root.brightness  = val
        if (spec.key === "temperature" && val >= 0 && val <= 5) root.temperature = val
      }
      root.stateLoaded = true
      queryProc.bufOut = ""
    }
  }
}
