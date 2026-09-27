import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Menu-summoned Logomarchy panel. Picks only redraw the preview, which is
// the vector logo drawn in QML; Apply renders the 4K file through
// scripts/omarchy-logomarchy and sets it as the wallpaper.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  property string theme: ""
  property string file: ""
  property bool active: false
  property string size: ""
  property string field: ""
  property string logo: ""
  property string pickSize: "default"
  property string pickField: "dark"
  property string pickLogo: "accent"
  property bool picksLoaded: false
  property bool shipsLogo: false
  property bool busy: false
  property var queued: null
  property var fieldOptions: []
  property var logoOptions: []
  property var pairs: ({})
  property string logoSvg: ""
  property int canvasWidth: 3840

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

  property var sizeOptions: [
    { value: "default", label: "Default", cellPx: 20 },
    { value: "small", label: "Small", cellPx: 12 },
    { value: "xsmall", label: "Extra small", cellPx: 7 }
  ]
  readonly property bool pickIsCurrent: file !== "" && active
    && pickSize === size && pickField === field && pickLogo === logo
  readonly property var visibleSections: file !== "" ? ["size", "field", "logo", "apply", "remove"] : ["size", "field", "logo", "apply"]
  readonly property var pickPair: pairs[pickField + ":" + pickLogo] || null
  readonly property bool adjusted: {
    if (!pickPair) return false
    var raw = optionHex(logoOptions, pickLogo)
    return raw !== "" && raw.toLowerCase() !== String(pickPair.logo).toLowerCase()
  }
  // The logo is 81 grid cells wide; cellPx is its cell size on the 4K canvas.
  readonly property real logoFraction: {
    for (var i = 0; i < sizeOptions.length; i++)
      if (sizeOptions[i].value === pickSize) return 81 * sizeOptions[i].cellPx / canvasWidth
    return 0.42
  }
  readonly property string previewLogoUrl: {
    if (logoSvg === "" || !pickPair) return ""
    return "data:image/svg+xml;utf8," + encodeURIComponent(logoSvg.split('fill="#000"').join('fill="' + pickPair.logo + '"'))
  }
  readonly property string styleCaption: {
    if (adjusted)
      return "Those two colors match, so the logo uses another theme color that still shows."
    if (pickField === "light" && pickLogo === "contrast")
      return "Light background, logo in the theme's dark color."
    if (pickField === "accent" && pickLogo === "background")
      return "Accent background, logo in the theme's background color."
    if (pickField === "dark" && pickLogo === "accent")
      return "Theme background, accent-colored logo. Matches the stock wallpapers."
    return optionLabel(fieldOptions, pickField) + " background, " + optionLabel(logoOptions, pickLogo).toLowerCase() + " logo."
  }

  component PaletteChip: Rectangle {
    id: chip

    property string label: ""
    property color swatch: "transparent"
    property bool selected: false
    property bool hasCursor: false
    signal clicked()
    signal hovered(bool isHovered)

    readonly property bool hot: mouse.containsMouse || hasCursor
    implicitWidth: chipRow.implicitWidth + Style.spacing.controlPaddingX * 2 + Style.space(2)
    implicitHeight: Math.max(chipRow.implicitHeight, Style.space(10)) + Style.spacing.controlPaddingY * 2 + Style.space(2)
    width: implicitWidth
    height: implicitHeight
    radius: Style.cornerRadius
    color: selected ? Style.selectedFillFor(root.foreground, root.accent)
         : hot ? Style.hoverFillFor(root.foreground, root.accent)
         : "transparent"
    border.width: Math.max(1, Style.spacing.hairline)
    border.color: selected || hot ? Qt.alpha(root.foreground, 0.72) : Qt.alpha(root.foreground, 0.28)

    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: Style.spacing.sm

      Rectangle {
        width: Style.space(10)
        height: width
        radius: width / 2
        color: chip.swatch
        border.width: Style.spacing.hairline
        border.color: Qt.alpha(root.foreground, 0.45)
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        text: chip.label
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      onClicked: chip.clicked()
      onContainsMouseChanged: chip.hovered(containsMouse)
    }
  }

  function optionLabel(options, value) {
    for (var i = 0; i < options.length; i++)
      if (options[i].value === value) return options[i].label
    return value
  }

  function optionHex(options, value) {
    for (var i = 0; i < options.length; i++)
      if (options[i].value === value) return String(options[i].hex || "")
    return ""
  }

  function hasOption(options, value) {
    for (var i = 0; i < options.length; i++)
      if (options[i].value === value) return true
    return false
  }

  function optionValue(options, index) {
    if (!options || index < 0 || index >= options.length) return ""
    return options[index].value
  }

  function open(payloadJson) {
    opened = true
    picksLoaded = false
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
    active = !!state.active
    shipsLogo = !!state.shipsLogo
    size = state.size || ""
    field = state.field || ""
    logo = state.logo || ""
    if (state.fields) fieldOptions = state.fields
    if (state.logos) logoOptions = state.logos
    if (state.sizes && state.sizes.length) sizeOptions = state.sizes
    if (state.pairs) pairs = state.pairs
    if (state.logoSvg) logoSvg = state.logoSvg
    if (state.canvas && state.canvas[0]) canvasWidth = state.canvas[0]

    // Start from the theme's saved variant, then leave the picks alone so
    // a refresh never overwrites what is being previewed.
    if (!picksLoaded) {
      pickSize = size || "default"
      pickField = field || "dark"
      pickLogo = logo || "accent"
      if (!hasOption(fieldOptions, pickField) && fieldOptions.length) pickField = fieldOptions[0].value
      if (!hasOption(logoOptions, pickLogo) && logoOptions.length) pickLogo = logoOptions[0].value
      picksLoaded = true
    }
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

  function apply() {
    if (pickIsCurrent) return
    run([bin, "generate", "--size", pickSize, "--field", pickField, "--logo", pickLogo, "--set"])
  }

  function remove() {
    run([bin, "remove"])
  }

  function sectionItem() {
    if (focusSection === "field") return chipAt(fieldFlow, selectedIndex)
    if (focusSection === "logo") return chipAt(logoFlow, selectedIndex)
    if (focusSection === "size") return sizeSection
    if (focusSection === "apply") return applyButton
    if (focusSection === "remove") return removeButton
    return null
  }

  function chipAt(flow, index) {
    if (!flow) return null
    var kids = flow.children
    for (var i = 0; i < kids.length; i++) {
      var kid = kids[i]
      if (kid && kid.index === index) return kid
    }
    return flow
  }

  function reveal(item) {
    if (!item || !scroll) return
    var pos = item.mapToItem(scroll, 0, 0)
    var margin = Style.space(8)
    if (pos.y < margin) scroll.contentY = Math.max(0, scroll.contentY + pos.y - margin)
    else if (pos.y + item.height > scroll.height - margin)
      scroll.contentY = scroll.contentY + pos.y + item.height - scroll.height + margin
    var maxY = Math.max(0, scroll.contentHeight - scroll.height)
    if (scroll.contentY > maxY) scroll.contentY = maxY
    if (scroll.contentY < 0) scroll.contentY = 0
  }

  function revealSoon() {
    Qt.callLater(function() { root.reveal(root.sectionItem()) })
  }

  function moveCursor(delta) {
    var sections = visibleSections
    var i = sections.indexOf(focusSection)
    var next = Math.max(0, Math.min(sections.length - 1, i + delta))
    if (next !== i) {
      focusSection = sections[next]
      selectedIndex = 0
      revealSoon()
    }
  }

  function moveCursorH(delta) {
    var count = focusSection === "size" ? sizeOptions.length
      : focusSection === "field" ? fieldOptions.length
      : focusSection === "logo" ? logoOptions.length
      : 1
    if (count < 1) return
    selectedIndex = Math.max(0, Math.min(count - 1, selectedIndex + delta))
    revealSoon()
  }

  function activateCursor() {
    var picked
    if (focusSection === "size") pickSize = optionValue(sizeOptions, selectedIndex) || pickSize
    else if (focusSection === "field") {
      picked = optionValue(fieldOptions, selectedIndex)
      if (picked) pickField = picked
    } else if (focusSection === "logo") {
      picked = optionValue(logoOptions, selectedIndex)
      if (picked) pickLogo = picked
    } else if (focusSection === "apply") apply()
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
      width: Math.min(Style.space(520), parent.width - Style.space(32))
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

        Flickable {
          id: scroll
          anchors.fill: parent
          contentWidth: width
          contentHeight: column.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height + 1

          Column {
            id: column
            width: scroll.width
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
              id: preview
              height: Math.min(Math.round(parent.width * 9 / 16), Style.space(200))
              width: Math.round(height * 16 / 9)
              anchors.horizontalCenter: parent.horizontalCenter
              radius: Style.cornerRadius
              color: root.pickPair ? root.pickPair.field : Qt.darker(root.background, 1.2)
              clip: true

              Image {
                anchors.centerIn: parent
                width: Math.round(preview.width * root.logoFraction)
                height: Math.round(width * 285 / 1215)
                sourceSize.width: width
                sourceSize.height: height
                source: root.previewLogoUrl
                smooth: true
                mipmap: false
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
              id: sizeSection
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
                value: root.pickSize
                options: root.sizeOptions
                onChanged: function(v) { root.pickSize = v }
                onHovered: function(index, on) {
                  if (!on) return
                  root.cursorActive = true
                  root.focusSection = "size"
                  root.selectedIndex = index
                }
              }
            }

            Column {
              id: fieldSection
              width: parent.width
              spacing: Style.space(6)

              PanelSectionHeader {
                text: "FIELD"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Grid {
                id: fieldFlow
                width: parent.width
                columns: Math.max(1, Math.min(4, Math.floor(width / Style.space(116))))
                rowSpacing: Style.spacing.md
                columnSpacing: Style.spacing.md

                Repeater {
                  model: root.fieldOptions

                  delegate: PaletteChip {
                    required property var modelData
                    required property int index
                    label: modelData.label
                    swatch: modelData.hex
                    selected: root.pickField === modelData.value
                    hasCursor: root.cursorActive && root.focusSection === "field" && root.selectedIndex === index
                    onClicked: root.pickField = modelData.value
                    onHovered: function(on) {
                      if (!on) return
                      root.cursorActive = true
                      root.focusSection = "field"
                      root.selectedIndex = index
                      root.revealSoon()
                    }
                  }
                }
              }
            }

            Column {
              id: logoSection
              width: parent.width
              spacing: Style.space(6)

              PanelSectionHeader {
                text: "LOGO"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Grid {
                id: logoFlow
                width: parent.width
                columns: Math.max(1, Math.min(4, Math.floor(width / Style.space(116))))
                rowSpacing: Style.spacing.md
                columnSpacing: Style.spacing.md

                Repeater {
                  model: root.logoOptions

                  delegate: PaletteChip {
                    required property var modelData
                    required property int index
                    label: modelData.label
                    swatch: modelData.hex
                    selected: root.pickLogo === modelData.value
                    hasCursor: root.cursorActive && root.focusSection === "logo" && root.selectedIndex === index
                    onClicked: root.pickLogo = modelData.value
                    onHovered: function(on) {
                      if (!on) return
                      root.cursorActive = true
                      root.focusSection = "logo"
                      root.selectedIndex = index
                      root.revealSoon()
                    }
                  }
                }
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.styleCaption
                color: Qt.darker(root.foreground, 1.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }

            Button {
              id: applyButton
              width: parent.width
              text: root.busy ? "Applying…"
                : root.pickIsCurrent ? "Current wallpaper"
                : "Set as wallpaper"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              bordered: true
              opacity: root.pickIsCurrent && !root.busy ? 0.55 : 1
              hasCursor: root.cursorActive && root.focusSection === "apply"
              onHovered: function(on) {
                if (!on) return
                root.cursorActive = true
                root.focusSection = "apply"
                root.selectedIndex = 0
                root.revealSoon()
              }
              onClicked: root.apply()
            }

            Button {
              id: removeButton
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
                root.revealSoon()
              }
              onClicked: root.remove()
            }
          }
        }
      }
    }
  }
}
