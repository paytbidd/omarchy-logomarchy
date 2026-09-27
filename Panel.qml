import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Menu-summoned Logomarchy panel. Every pick regenerates the current
// theme's logo wallpaper through scripts/omarchy-logomarchy and shows it.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  property string theme: ""
  property string file: ""
  property string size: "default"
  property string style: "dark"
  property bool shipsLogo: false
  property bool busy: false
  property var queued: null

  property string focusSection: "size"
  property int selectedIndex: 0
  property bool cursorActive: false

  readonly property string pluginId: (manifest && manifest.id) || "payton.logomarchy"
  readonly property string bin: {
    var home = Quickshell.env("HOME") || ""
    return home + "/.config/omarchy/plugins/payton.logomarchy/scripts/omarchy-logomarchy"
  }
  readonly property color foreground: Color.foreground
  readonly property color background: Color.popups.background
  readonly property color accent: Color.accent
  readonly property string fontFamily: Style.font.family

  readonly property var sizeOptions: [
    { value: "default", label: "Default" },
    { value: "small", label: "Small" },
    { value: "xsmall", label: "Extra small" }
  ]
  readonly property var styleOptions: [
    { value: "dark", label: "Dark" },
    { value: "accent", label: "Accent" }
  ]
  readonly property var visibleSections: file !== "" ? ["size", "style", "remove"] : ["size", "style"]

  function open(payloadJson) {
    opened = true
    cursorActive = false
    focusSection = "size"
    selectedIndex = 0
    refresh()
    Qt.callLater(function() {
      if (root.opened && keyCatcher) keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    opened = false
  }

  function dismiss() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  function refresh() {
    if (!getProc.running) getProc.running = true
  }

  function applyState(raw) {
    var state
    try { state = JSON.parse(String(raw).trim()) } catch (e) { return }
    theme = state.theme || ""
    file = state.file || ""
    shipsLogo = !!state.shipsLogo
    if (state.size) size = state.size
    if (state.style) style = state.style
  }

  function run(args) {
    if (runProc.running) {
      queued = args
      return
    }
    queued = null
    busy = true
    runProc.command = args
    runProc.running = true
  }

  function generate(nextSize, nextStyle) {
    size = nextSize
    style = nextStyle
    run([bin, "generate", "--size", nextSize, "--style", nextStyle, "--set"])
  }

  function remove() {
    run([bin, "remove"])
  }

  function moveCursor(delta) {
    var sections = visibleSections
    var i = sections.indexOf(focusSection)
    var next = Math.max(0, Math.min(sections.length - 1, i + delta))
    if (next !== i) {
      focusSection = sections[next]
      selectedIndex = 0
    }
  }

  function moveCursorH(delta) {
    var count = focusSection === "size" ? sizeOptions.length : focusSection === "style" ? styleOptions.length : 1
    selectedIndex = Math.max(0, Math.min(count - 1, selectedIndex + delta))
  }

  function activateCursor() {
    if (focusSection === "size") generate(sizeOptions[selectedIndex].value, style)
    else if (focusSection === "style") generate(size, styleOptions[selectedIndex].value)
    else if (focusSection === "remove") remove()
  }

  Process {
    id: getProc
    command: [root.bin, "get", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (!runProc.running) root.applyState(text)
    }
  }

  Process {
    id: runProc
    onRunningChanged: {
      if (running) return
      if (root.queued) {
        var args = root.queued
        root.queued = null
        command = args
        running = true
        return
      }
      root.busy = false
      root.refresh()
    }
  }

  PanelWindow {
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-logomarchy"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.42)
      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }
    }

    BorderSurface {
      id: card
      width: Math.min(Style.space(420), parent.width - Style.space(32))
      height: Math.min(column.implicitHeight + card.contentTopInset + card.contentBottomInset, parent.height - Style.space(32))
      anchors.centerIn: parent
      color: root.background
      radius: Style.cornerRadius
      padding: Style.spacing.popupPadding
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
      }

      PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        onMoveRequested: function(dx, dy) {
          if (!root.cursorActive) { root.cursorActive = true; return }
          if (dy !== 0) root.moveCursor(dy)
          else if (dx !== 0) root.moveCursorH(dx)
        }
        onActivateRequested: if (root.cursorActive) root.activateCursor()
        onCloseRequested: root.dismiss()

        Column {
          id: column
          width: parent.width
          spacing: Style.space(14)

          PanelHero {
            width: parent.width
            foreground: root.foreground
            fontFamily: root.fontFamily
            title: "Logomarchy"
            meta: root.theme !== "" ? root.theme : "No theme"
            iconComponent: Component {
              Text {
                text: "󰸉"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Rectangle {
            width: parent.width
            height: Math.round(width * 9 / 16)
            radius: Style.cornerRadius
            color: Qt.darker(root.background, 1.2)
            clip: true

            Image {
              anchors.fill: parent
              source: root.file !== "" ? "file://" + root.file : ""
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              cache: false
              smooth: true
              sourceSize.width: 840
            }

            Text {
              anchors.centerIn: parent
              visible: root.file === ""
              width: parent.width - Style.space(32)
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: root.shipsLogo
                ? "This theme ships its own logo wallpaper. Pick a size or style to make one of your own."
                : "Pick a size or style to make a logo wallpaper for this theme."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Rectangle {
              anchors.fill: parent
              radius: parent.radius
              color: "transparent"
              border.width: Style.spacing.hairline
              border.color: Qt.alpha(root.foreground, 0.32)
              antialiasing: radius > 0
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "SIZE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ButtonGroup {
              width: parent.width
              foreground: root.foreground
              background: root.background
              accent: root.accent
              fontFamily: root.fontFamily
              focusable: false
              cursorIndex: root.cursorActive && root.focusSection === "size" ? root.selectedIndex : -1
              value: root.file !== "" ? root.size : ""
              options: root.sizeOptions
              onChanged: function(v) { root.generate(v, root.style) }
              onHovered: function(index, on) {
                if (!on) return
                root.cursorActive = true
                root.focusSection = "size"
                root.selectedIndex = index
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "STYLE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ButtonGroup {
              width: parent.width
              foreground: root.foreground
              background: root.background
              accent: root.accent
              fontFamily: root.fontFamily
              focusable: false
              cursorIndex: root.cursorActive && root.focusSection === "style" ? root.selectedIndex : -1
              value: root.file !== "" ? root.style : ""
              options: root.styleOptions
              onChanged: function(v) { root.generate(root.size, v) }
              onHovered: function(index, on) {
                if (!on) return
                root.cursorActive = true
                root.focusSection = "style"
                root.selectedIndex = index
              }
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.style === "accent"
                ? "Accent background, logo in the theme's background color."
                : "Theme background, accent-colored logo."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Button {
            visible: root.file !== ""
            width: parent.width
            text: "Remove from this theme"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            bordered: true
            hasCursor: root.cursorActive && root.focusSection === "remove"
            onHovered: function(on) {
              if (!on) return
              root.cursorActive = true
              root.focusSection = "remove"
              root.selectedIndex = 0
            }
            onClicked: root.remove()
          }
        }
      }
    }
  }
}
