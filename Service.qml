import QtQuick
import Quickshell
import Quickshell.Io
import "Channels.js" as Channels

// Playback and stream state live here rather than in the bar widget: a bar
// surface is instantiated per monitor, so widget-owned mpv processes would
// mean one stream per screen and per-screen disagreement about what is
// playing. The widget is a pure view over this singleton.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/sprawlfm"
  readonly property var channels: Channels.list

  property int channelIndex: 0
  readonly property var channel: channels[channelIndex]
  readonly property bool playing: mpvProc.running

  // Stream volume, 0-100, mpv's own scale. Separate from the system volume so
  // the radio can sit under other audio. Persisted beside the channel.
  property int volume: 100
  property int ipcAttempts: 0
  readonly property string mpvSocketPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/sprawlfm-mpv.sock"

  // Settings read off this plugin's entry in shell.json, so `omarchy bar set
  // bhj.sprawlfm <key> <value>` and hand edits both take effect live.
  readonly property var shellConfig: shell ? shell.shellConfig : null
  readonly property int refreshIntervalSec: Math.max(5, Channels.widgetSetting(shellConfig, "bhj.sprawlfm", "refreshIntervalSec", 15))
  readonly property string defaultChannel: String(Channels.widgetSetting(shellConfig, "bhj.sprawlfm", "defaultChannel", ""))
  readonly property int defaultChannelIndex: Channels.indexOfSlug(defaultChannel)

  // Startup picks the configured default when there is one, otherwise the
  // channel last tuned. Resolved exactly once: a later `omarchy bar set`
  // updates which row is marked default without yanking the session off the
  // channel currently playing.
  property bool channelResolved: false

  function resolveInitialChannel() {
    if (channelResolved) return
    channelResolved = true
    if (defaultChannelIndex >= 0) channelIndex = defaultChannelIndex
  }

  // Last parsed /status-json.xsl payload. Kept across failed polls so a
  // dropped request leaves the previous track on screen instead of blanking.
  property var status: null
  readonly property var source: status ? Channels.sourceForMount(status, channel.mount) : null
  readonly property string trackTitle: Channels.titleOf(source)
  readonly property int listeners: Channels.listenersOf(source)

  // Set when a channel change kills a running mpv: the relaunch has to wait
  // for the exit, otherwise the new process races the old one's teardown.
  property bool restartPending: false

  function sourceFor(mount) {
    return status ? Channels.sourceForMount(status, mount) : null
  }

  function play() {
    if (mpvProc.running) return
    mpvProc.command = [
      "mpv", "--no-video", "--no-terminal", "--really-quiet",
      "--stream-lavf-o=reconnect=1,reconnect_streamed=1,reconnect_delay_max=5",
      "--volume=" + volume,
      "--input-ipc-server=" + mpvSocketPath,
      Channels.streamUrl(channel.mount)
    ]
    mpvProc.running = true
  }

  // Live changes go to the running mpv over its JSON IPC socket, so the
  // stream never restarts; a stopped stream just picks the value up through
  // --volume on the next play. `persist` is false while a slider is dragging
  // so the state file is written once, on release.
  function setVolume(v, persist) {
    var next = Math.max(0, Math.min(100, Math.round(Number(v))))
    if (isNaN(next)) return
    volume = next
    ipcAttempts = 0
    sendVolume()
    if (persist !== false) volumeFile.setText(String(next) + "\n")
  }

  function sendVolume() {
    if (!mpvProc.running) return
    if (mpvIpc.connected) {
      mpvIpc.write(JSON.stringify({ command: ["set_property", "volume", root.volume] }) + "\n")
      mpvIpc.flush()
    } else if (ipcAttempts < 10) {
      ipcAttempts++
      // mpv creates the socket a moment after launch; connecting sends the
      // current value, and the retry covers a connect that beat the socket.
      mpvIpc.connected = true
      ipcRetry.restart()
    }
  }

  function stop() {
    restartPending = false
    mpvProc.running = false
  }

  function toggle() {
    if (mpvProc.running) stop()
    else play()
  }

  function tune(index) {
    if (index < 0 || index >= channels.length) return
    if (index === channelIndex) return
    channelIndex = index
    channelFile.setText(channels[index].slug + "\n")
    if (mpvProc.running) {
      restartPending = true
      mpvProc.running = false
    }
    refresh()
  }

  function step(delta) {
    var n = channels.length
    tune(((channelIndex + delta) % n + n) % n)
  }

  function next() { step(1) }
  function previous() { step(-1) }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  IpcHandler {
    target: "bhj.sprawlfm"

    function toggle(): void { root.toggle() }
    function play(): void { root.play() }
    function stop(): void { root.stop() }
    function next(): void { root.next() }
    function previous(): void { root.previous() }
    function refresh(): void { root.refresh() }
    function channel(): string { return root.channel.slug }
    function setVolume(percent: int): void { root.setVolume(percent, true) }
    function getVolume(): int { return root.volume }
    function state(): string {
      return JSON.stringify({
        playing: root.playing,
        channel: root.channel.slug,
        name: root.channel.name,
        title: root.trackTitle,
        listeners: root.listeners,
        volume: root.volume
      })
    }
  }

  Process {
    id: stateDirProc
    command: ["mkdir", "-p", root.stateDir]
    running: true
  }

  // Plain slug, one line. Written on every tune so the selection survives a
  // shell restart; an unknown slug (renamed channel) falls back to the first.
  FileView {
    id: channelFile
    path: root.stateDir + "/channel"
    atomicWrites: true
    printErrors: false
    onLoaded: {
      if (root.channelResolved) return
      // The remembered channel is the fallback, not an override: an explicit
      // defaultChannel setting wins and is applied by resolveInitialChannel.
      if (root.defaultChannelIndex < 0) {
        var index = Channels.indexOfSlug(String(text() || "").trim())
        if (index >= 0) root.channelIndex = index
      }
      root.resolveInitialChannel()
    }
    onLoadFailed: root.resolveInitialChannel()
  }

  // Backstop: a configured default must still land if the state file neither
  // loads nor fails (missing dir racing stateDirProc, for instance). Armed
  // only when a default exists — running it unconditionally would let it beat
  // a slow file load and mark the channel resolved, discarding the remembered
  // channel it was meant to be a fallback for.
  Timer {
    interval: 1000
    running: root.defaultChannelIndex >= 0
    repeat: false
    onTriggered: root.resolveInitialChannel()
  }

  FileView {
    id: volumeFile
    path: root.stateDir + "/volume"
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var v = parseInt(String(text() || "").trim(), 10)
      if (!isNaN(v)) root.volume = Math.max(0, Math.min(100, v))
    }
  }

  Socket {
    id: mpvIpc
    path: root.mpvSocketPath
    // Replies are not needed; read them so they do not pile up.
    parser: SplitParser { onRead: function(data) {} }
    onConnectedChanged: if (connected) { root.ipcAttempts = 0; root.sendVolume() }
  }

  Timer {
    id: ipcRetry
    interval: 400
    repeat: false
    onTriggered: if (mpvProc.running && !mpvIpc.connected) root.sendVolume()
  }

  Process {
    id: mpvProc
    onExited: {
      mpvIpc.connected = false
      if (!root.restartPending) return
      root.restartPending = false
      Qt.callLater(root.play)
    }
  }

  Process {
    id: statusProc
    command: ["curl", "-fsS", "--max-time", "10", "--max-filesize", "262144", "https://sprawlfm.com/status-json.xsl"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) return
        try {
          root.status = JSON.parse(raw)
        } catch (e) {
          // Keep the last good payload rather than clearing the label.
        }
      }
    }
  }

  Timer {
    interval: Math.max(5, root.refreshIntervalSec) * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
