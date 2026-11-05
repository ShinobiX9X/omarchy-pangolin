import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.shinobix9x.pangolin"
  ipcTarget: "io.github.shinobix9x.pangolin"
  manageIpc: false

  readonly property string ctl: String(Qt.resolvedUrl("pangolin-ctl.sh")).replace(/^file:\/\//, "")

  // Client state, filled from `pangolin status --json`.
  property bool installed: true
  property bool running: false
  property bool connected: false
  property bool registered: false
  property string orgId: ""
  property string version: ""
  property string address: ""
  property string statusError: ""
  property var sites: []

  // Toggle state.
  property bool busy: false
  property string pendingAction: ""
  property string lastError: ""
  property int settleTicks: 0

  readonly property bool isUp: running && !statusTerminated
  property bool statusTerminated: false
  readonly property string clientState: !installed ? "missing"
    : busy ? "busy"
    : !isUp ? "off"
    : statusError !== "" ? "error"
    : connected && registered ? "on"
    : "connecting"
  readonly property string stateText: ({
    "missing": "Pangolin CLI not found",
    "busy": pendingAction === "up" ? "Connecting…" : "Disconnecting…",
    "off": "Disconnected",
    "error": statusError,
    "on": "Connected",
    "connecting": "Connecting…"
  })[clientState]
  readonly property int sitesUp: sites.filter(function(s) { return s.connected }).length

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string glyph: "󰖂"

  readonly property int refreshMs: Math.max(2, Number(setting("refreshIntervalSec", 10))) * 1000
  readonly property bool hideWhenOff: setting("hideWhenOff", false) === true

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function setUp(wantOn) {
    if (busy || !installed || wantOn === isUp) return
    busy = true
    lastError = ""
    pendingAction = wantOn ? "up" : "down"
    toggleProc.command = ["bash", ctl, pendingAction]
    toggleProc.running = true
  }

  function toggleClient() { setUp(!isUp) }

  function applyStatus(text) {
    var s
    try { s = JSON.parse(text) } catch (e) { return }
    installed = s.installed !== false
    if (s.running === false) {
      running = false
      connected = registered = statusTerminated = false
      statusError = ""
      sites = []
      address = ""
      return
    }
    running = true
    connected = !!s.connected
    registered = !!s.registered
    statusTerminated = !!s.terminated
    orgId = s.orgId || ""
    version = s.version || ""
    statusError = s.error ? String(s.error.message || s.error.code || "Error") : ""
    var net = s.networkSettings || {}
    address = (net.ipv4_addresses && net.ipv4_addresses[0]) || ""
    var list = []
    var peers = s.peers || {}
    for (var id in peers) {
      var p = peers[id]
      list.push({
        name: p.name || ("Site " + id),
        connected: !!p.connected,
        relay: !!p.isRelay,
        local: !!p.isLocal,
        rttMs: p.rtt ? Math.round(p.rtt / 1e6) : 0,
        endpoint: p.endpoint || "",
        lastSeen: p.lastSeen || ""
      })
    }
    list.sort(function(a, b) { return a.name.localeCompare(b.name) })
    sites = list
  }

  function siteMeta(site) {
    var parts = [site.local ? "Local" : site.relay ? "Relay" : "Direct"]
    if (site.connected && site.rttMs > 0) parts.push(site.rttMs + " ms")
    if (!site.connected && site.lastSeen) parts.push("seen " + ago(site.lastSeen))
    return parts.join(" · ")
  }

  function ago(iso) {
    var t = Date.parse(iso)
    if (isNaN(t) || t < 86400000) return "never"
    var s = Math.max(0, Math.round((Date.now() - t) / 1000))
    if (s < 60) return s + "s ago"
    if (s < 3600) return Math.round(s / 60) + "m ago"
    if (s < 86400) return Math.round(s / 3600) + "h ago"
    return Math.round(s / 86400) + "d ago"
  }

  readonly property string tooltip: "Pangolin: " + stateText
    + (isUp && orgId ? " · " + orgId : "")
    + (isUp && sites.length ? " · " + sitesUp + "/" + sites.length + " sites" : "")
    + (lastError ? "\n" + lastError : "")

  visible: !(hideWhenOff && clientState === "off" && !opened)
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Process {
    id: statusProc
    command: ["bash", root.ctl, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(String(text).trim())
    }
  }

  Process {
    id: toggleProc
    stderr: StdioCollector { id: toggleErr; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) {
        var msg = String(toggleErr.text).replace(/\x1b\[[0-9;]*m/g, "").trim().split("\n").pop()
        root.lastError = code === 126
          ? "Authentication cancelled"
          : (msg || ("pangolin " + root.pendingAction + " failed (" + code + ")"))
      }
      root.busy = false
      root.settleTicks = 15
      root.refresh()
    }
  }

  // Poll slowly in the background, quickly while the popup is open or the
  // client is still coming up / going down.
  Timer {
    interval: root.opened || root.settleTicks > 0 || root.clientState === "connecting" ? 1500 : root.refreshMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (root.settleTicks > 0) root.settleTicks--
      root.refresh()
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function up(): void { root.setUp(true) }
    function down(): void { root.setUp(false) }
    function toggleClient(): void { root.toggleClient() }
    function refresh(): void { root.refresh() }
    function status(): string { return root.clientState }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    active: root.clientState === "error" || (root.lastError !== "" && !root.isUp)
    dimmed: root.clientState === "off" || root.clientState === "missing"
    tooltipText: root.opened ? "" : root.tooltip
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.toggleClient()
      else if (buttonCode === Qt.RightButton) root.refresh()
      else root.toggle()
    }

    SequentialAnimation on opacity {
      running: root.clientState === "busy" || root.clientState === "connecting"
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutQuad }
      NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onActivateRequested: root.toggleClient()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === " " || t === "t" || t === "T") root.toggleClient()
        else if (t === "r" || t === "R") root.refresh()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: "Pangolin"
            meta: root.stateText
            detail: root.isUp ? root.orgId : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.clientState === "on" ? 1.0 : 0.5
            iconComponent: Component {
              Text {
                text: root.glyph
                color: root.clientState === "error" ? root.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: Component {
              ToggleSwitch {
                id: powerSwitch
                visible: root.installed
                checked: root.busy ? root.pendingAction === "up" : root.isUp
                busy: root.busy
                foreground: hero.foreground
                onToggled: root.toggleClient()

                PanelToolTip {
                  visible: powerSwitch.containsMouse
                  text: root.isUp ? "Disconnect" : "Connect (asks for your password)"
                  fontFamily: hero.fontFamily
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.lastError !== "" || root.clientState === "missing"
            width: parent.width
            text: root.clientState === "missing"
              ? "Install the Pangolin CLI (pangolin.net/downloads) and log in with `pangolin login`."
              : root.lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            visible: root.isUp
            width: parent.width
            spacing: Style.spacing.labelGap
            InfoPair { label: "Address"; value: root.address || "—" }
            InfoPair { label: "Client"; value: root.version || "—" }
          }

          PanelSeparator {
            visible: root.isUp
            foreground: root.foreground
          }

          Column {
            visible: root.isUp
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "SITES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: root.sites.length === 0
              width: parent.width
              text: "No sites yet."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Repeater {
              model: root.sites
              SiteRow {
                required property var modelData
                width: column.width
                site: modelData
              }
            }
          }
        }
      }
    }
  }

  component SiteRow: RowLayout {
    property var site: null
    spacing: Style.space(10)

    Rectangle {
      Layout.alignment: Qt.AlignVCenter
      implicitWidth: Style.space(8)
      implicitHeight: Style.space(8)
      radius: width / 2
      color: site && site.connected ? root.foreground : "transparent"
      border.width: 1
      border.color: site && site.connected ? root.foreground : root.dim
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(1)

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: site ? site.name : ""
        color: site && site.connected ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: site ? root.siteMeta(site) : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    Text {
      textFormat: Text.PlainText
      text: label
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    Text {
      textFormat: Text.PlainText
      text: value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }
  }
}
