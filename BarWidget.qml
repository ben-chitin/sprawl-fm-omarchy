import QtQuick
import Quickshell
import qs.Ui
import qs.Commons
import "Channels.js" as Channels

BarWidget {
  id: root
  moduleName: "bhj.sprawlfm"

  // All playback and stream state is owned by the plugin's service singleton
  // so every monitor's bar shows the same thing and only one mpv ever runs.
  readonly property var service: bar?.shell?.serviceFor("bhj.sprawlfm") ?? null
  readonly property var channels: service ? service.channels : Channels.list
  readonly property var channel: service ? service.channel : Channels.list[0]
  readonly property bool playing: service ? service.playing : false
  readonly property string trackTitle: service ? service.trackTitle : ""
  readonly property int listeners: service ? service.listeners : -1
  readonly property int volume: service ? service.volume : 100

  function nudgeVolume(delta) {
    if (service) service.setVolume(volume + delta, true)
  }

  readonly property real maxLabelWidth: setting("maxLabelWidth", 180)
  readonly property color fg: bar ? bar.barForeground : "white"
  readonly property color panelFg: bar ? bar.foreground : "white"

  property bool showStation: false
  readonly property bool showTrackTitle: setting("showTrackTitle", false) === true
  readonly property string stationLabel: channel.slug === "all" ? "ALL FREQ" : channel.name
  readonly property string label: showTrackTitle ? (trackTitle || "No track information") : (showStation ? stationLabel : "SPRAWL")

  Timer {
    interval: 9000 + Style.duration(1000)
    running: !root.showTrackTitle
    repeat: true
    onTriggered: root.showStation = !root.showStation
  }
  readonly property string tooltip: channel.name
    + (trackTitle !== "" ? " · " + trackTitle : "")
    + (listeners >= 0 ? " · " + listeners + " listening" : "")

  property bool popupOpen: false

  // Shape contract Bar.findPanelWidget looks for, so the channel list can be
  // summoned with `omarchy-shell shell toggle bhj.sprawlfm` and bound to a key.
  readonly property bool opened: popupOpen

  function open() { popupOpen = true }
  function close() { popupOpen = false }
  function togglePanel() { popupOpen = !popupOpen }

  // Keyboard cursor over the channel list, as the stock panels have one: the
  // first arrow press shows it on the channel playing, and it is gone again
  // each time the panel opens.
  property bool cursorActive: false
  property int cursorIndex: 0
  onPopupOpenChanged: if (popupOpen) cursorActive = false

  function moveCursor(dy) {
    var count = channels.length
    if (count === 0) return
    if (!cursorActive) {
      cursorActive = true
      cursorIndex = Math.max(0, channels.indexOf(channel))
      return
    }
    cursorIndex = (cursorIndex + dy + count) % count
  }

  function activateCursor() {
    if (!service) return
    if (!cursorActive) { service.toggle(); return }
    service.tune(cursorIndex)
    service.play()
  }

  function handleClick(button) {
    if (!service) return
    if (button === Qt.RightButton) popupOpen = !popupOpen
    else if (button === Qt.MiddleButton) { if (bar) bar.run("omarchy-launch-browser https://sprawlfm.com") }
    else service.toggle()
  }

  function handleWheel(wheel) {
    if (!service) return
    if (wheel.angleDelta.y > 0) service.previous()
    else if (wheel.angleDelta.y < 0) service.next()
  }

  // Writing through `omarchy bar set` rather than editing shell.json here: the
  // shell owns that file, and the command is the same path the CLI and any
  // future settings UI take. The service picks the change back up off the
  // reloaded config. An empty value clears the default, restoring
  // remember-the-last-channel behavior.
  function setDefaultChannel(slug, clearing) {
    if (!bar) return
    bar.run("omarchy bar set bhj.sprawlfm defaultChannel " + bar.shellQuote(clearing ? "" : slug))
  }

  implicitWidth: vertical ? barSize : row.implicitWidth + Style.space(14)
  implicitHeight: barSize

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    Item {
      id: glyphSlot
      width: glyph.implicitWidth
      height: root.barSize
      anchors.verticalCenter: parent.verticalCenter

      Text {
        id: glyph
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.playing ? "󰏤" : "󰐊"
        color: root.playing ? root.fg : Qt.darker(root.fg, 1.5)
        font.family: root.bar ? root.bar.fontFamily : "monospace"
        font.pixelSize: Style.font.body
        Behavior on color {
          enabled: !root.bar || root.bar.foregroundAnimationEnabled
          ColorAnimation { duration: 160 }
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: function(mouse) { root.handleClick(mouse.button) }
        onWheel: function(wheel) { root.handleWheel(wheel) }
        onEntered: if (root.bar) root.bar.showTooltip(glyphSlot, root.playing ? "Pause SPRAWL FM" : "Tune in to SPRAWL FM")
        onExited: if (root.bar) root.bar.hideTooltip(glyphSlot)
      }
    }

    Item {
      id: scrollClip
      width: Math.min(root.maxLabelWidth, Math.max(brandText.implicitWidth, stationText.implicitWidth))
      height: root.barSize
      clip: true
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.vertical && root.label !== ""

      Text {
        id: brandText
        textFormat: Text.PlainText
        text: "SPRAWL"
        color: root.fg
        font.family: root.bar ? root.bar.fontFamily : "monospace"
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
        x: root.showStation || root.showTrackTitle ? -scrollClip.width : 0
        Behavior on x { NumberAnimation { duration: Style.duration(1000); easing.type: Easing.OutCubic } }
      }

      Text {
        id: stationText
        textFormat: Text.PlainText
        text: root.showTrackTitle ? (root.trackTitle || "No track information") : root.stationLabel
        color: root.fg
        font.family: root.bar ? root.bar.fontFamily : "monospace"
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, scrollClip.width)
        elide: Text.ElideRight
        x: root.showStation || root.showTrackTitle ? 0 : scrollClip.width
        Behavior on x { NumberAnimation { duration: Style.duration(1000); easing.type: Easing.OutCubic } }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: function(mouse) {
          if (mouse.button === Qt.LeftButton) root.popupOpen = !root.popupOpen
          else root.handleClick(mouse.button)
        }
        onWheel: function(wheel) { root.handleWheel(wheel) }
        onEntered: if (root.bar) root.bar.showTooltip(scrollClip, root.tooltip.replace(/</g, "‹").replace(/>/g, "›"))
        onExited: if (root.bar) root.bar.hideTooltip(scrollClip)
      }
    }
  }

  // A layer-shell panel like the stock dropdowns, not an xdg-popup off the
  // bar: it takes the keyboard when summoned, and Glassy's layer rule frosts
  // it along with them.
  KeyboardPanel {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(320))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.nudgeVolume(dx > 0 ? 5 : -5)
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTextKey: function(t, modifiers) {
        if (t === "d" && root.cursorActive && root.service) {
          var c = root.channels[root.cursorIndex]
          root.setDefaultChannel(c.slug, root.cursorIndex === root.service.defaultChannelIndex)
        }
      }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(10)

        Row {
          spacing: Style.space(10)
          width: parent.width

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "󰝚"
            color: root.panelFg
            font.family: root.bar ? root.bar.fontFamily : "monospace"
            font.pixelSize: Style.font.displayLarge
          }

          Column {
            spacing: Style.space(2)
            width: parent.width - Style.space(40)

            Text {
              textFormat: Text.PlainText
              text: root.trackTitle || (root.playing ? "Tuning in…" : "Off air")
              color: root.panelFg
              font.family: root.bar ? root.bar.fontFamily : "monospace"
              font.pixelSize: Style.font.subtitle
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: "SPRAWL FM · " + root.channel.name + " · 128k mp3"
              color: Qt.darker(root.panelFg, 1.3)
              font.family: root.bar ? root.bar.fontFamily : "monospace"
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: root.listeners >= 0 ? root.listeners + " listening" : ""
              color: Qt.darker(root.panelFg, 1.6)
              font.family: root.bar ? root.bar.fontFamily : "monospace"
              font.pixelSize: Style.font.caption
              visible: text !== ""
            }
          }
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(6)

          Button {
            iconText: "󰒮"
            foreground: root.panelFg
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: if (root.service) root.service.previous()
          }

          Button {
            iconText: root.playing ? "󰏤" : "󰐊"
            foreground: root.panelFg
            horizontalPadding: Style.spacing.panelGap
            verticalPadding: Style.spacing.controlPaddingY
            iconSize: Style.font.iconLarge
            onClicked: if (root.service) root.service.toggle()
          }

          Button {
            iconText: "󰒭"
            foreground: root.panelFg
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: if (root.service) root.service.next()
          }
        }

        Item {
          id: volumeRow
          width: parent.width
          implicitHeight: volumeSlider.implicitHeight

          Text {
            id: volumeIcon
            textFormat: Text.PlainText
            text: root.volume === 0 ? "󰝟" : (root.volume < 50 ? "󰖀" : "󰕾")
            color: root.panelFg
            font.family: root.bar ? root.bar.fontFamily : "monospace"
            font.pixelSize: Style.font.body
            width: Style.space(18)
            horizontalAlignment: Text.AlignHCenter
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          PanelSlider {
            id: volumeSlider
            bar: root.bar
            anchors.left: volumeIcon.right
            anchors.right: volumePercent.left
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            minimum: 0
            maximum: 100
            step: 5
            integer: true
            value: root.volume
            // Live while dragging, saved once on release.
            onMoved: function(v) { if (root.service) root.service.setVolume(v, false) }
            onReleased: function(v) { if (root.service) root.service.setVolume(v, true) }
          }

          Text {
            id: volumePercent
            textFormat: Text.PlainText
            text: Math.round(volumeSlider.dragging ? volumeSlider.liveValue : root.volume) + "%"
            color: Qt.darker(root.panelFg, 1.4)
            font.family: root.bar ? root.bar.fontFamily : "monospace"
            font.pixelSize: Style.font.caption
            font.bold: true
            width: Style.space(36)
            horizontalAlignment: Text.AlignRight
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Button {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.showTrackTitle ? "Hide track title from bar" : "Show track title on bar"
          foreground: root.panelFg
          bordered: true
          focusable: true
          onClicked: if (root.bar) root.bar.run("omarchy bar set bhj.sprawlfm showTrackTitle " + (root.showTrackTitle ? "false" : "true") + " --json")
        }

        PanelSeparator { foreground: root.panelFg }

        Column {
          id: channelList
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: root.channels

            BorderSurface {
              id: channelRow
              required property int index
              required property var modelData

              readonly property var info: root.service ? root.service.sourceFor(modelData.mount) : null
              readonly property bool selected: root.channel && index === root.channels.indexOf(root.channel)
              readonly property bool isDefault: root.service && index === root.service.defaultChannelIndex
              readonly property bool hasCursor: root.cursorActive && index === root.cursorIndex
              readonly property string detail: {
                var parts = []
                var genre = Channels.genreOf(info)
                if (genre !== "") parts.push(genre)
                var live = Channels.listenersOf(info)
                if (live >= 0) parts.push(live + " listening")
                if (isDefault) parts.push("default")
                return parts.join(" · ")
              }

              width: channelList.width
              height: rowInner.implicitHeight + Style.space(10)
              radius: Style.spacing.labelGap
              color: selected ? Style.selectedFillFor(root.panelFg, Color.accent) : "transparent"
              borderSpec: selected || hasCursor ? Border.controlSpec(hasCursor ? "focus" : "normal", root.panelFg, Color.accent) : Border.none()

              Row {
                id: rowInner
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: channelRow.borderLeft + Style.space(8)
                anchors.rightMargin: channelRow.borderRight + Style.space(8)
                spacing: Style.space(8)

                Text {
                  textFormat: Text.PlainText
                  text: channelRow.selected && root.playing ? "󰏤" : "󰐊"
                  color: root.panelFg
                  font.family: root.bar ? root.bar.fontFamily : "monospace"
                  font.pixelSize: Style.font.body
                  width: Style.space(18)
                  horizontalAlignment: Text.AlignHCenter
                  anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                  width: parent.width - Style.space(26)
                  spacing: Style.space(1)
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    textFormat: Text.PlainText
                    text: channelRow.modelData.name
                    color: root.panelFg
                    font.family: root.bar ? root.bar.fontFamily : "monospace"
                    font.pixelSize: Style.font.bodySmall
                    font.bold: channelRow.selected
                    elide: Text.ElideRight
                    width: parent.width
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: channelRow.detail
                    color: Qt.darker(root.panelFg, 1.5)
                    font.family: root.bar ? root.bar.fontFamily : "monospace"
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    width: parent.width
                    visible: text !== ""
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: function(mouse) {
                  if (!root.service) return
                  if (mouse.button === Qt.RightButton) {
                    root.setDefaultChannel(channelRow.modelData.slug, channelRow.isDefault)
                    return
                  }
                  root.service.tune(channelRow.index)
                  root.service.play()
                }
                onEntered: if (root.bar) root.bar.showTooltip(channelRow,
                  channelRow.isDefault ? "Left: tune in · Right: clear default"
                                       : "Left: tune in · Right: make default")
                onExited: if (root.bar) root.bar.hideTooltip(channelRow)
              }
            }
          }
        }
      }
    }
  }
}
