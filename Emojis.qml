import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "EmojiSearch.js" as EmojiSearch

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property var emojis: []
  property string mode: "emoji"

  // Nerd Font search streams from nerdfonts.tsv via grep instead of
  // holding the whole dataset in memory: only matched rows are resident.
  property int nerdSearchSeq: 0
  property int nerdRunningSeq: 0
  property var nerdActiveTokens: []
  property var nerdRows: []
  property var nerdPendingCmd: null
  readonly property string tsvPath: Qt.resolvedUrl("nerdfonts.tsv").toString().replace("file://", "")

  // Kaomoji rows parse from kaomoji.tsv on first tab activation (the
  // FileView's preload stays false until then) and live in memory —
  // ~1.5k short rows, unlike the grep-streamed nerd dataset. Null until
  // that first load lands.
  property var kaomojiRows: null
  readonly property var modeOrder: ["emoji", "nerd", "kaomoji"]

  // Shares the [menu] surface tokens — themes that style the menu also
  // style emojis. Selected-cell colors composed in the
  // singleton so consumers drop them straight into Rectangle bindings.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int cardWidth: Math.min(Style.space(400), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(500), panel.height - Style.gapsOut * 2)

  property int cellWidth: Math.max(Style.space(44), Style.font.display + Style.spacing.md)
  property int cellHeight: Math.max(Style.space(44), Style.font.display + Style.spacing.md)
  property int columns: Math.floor((cardWidth - contentMargin * 2) / cellWidth)

  property int listRowHeight: Math.max(Style.space(32), Style.font.title + Style.spacing.md)

  property int footerHeight: root.mode === "nerd" ? Style.space(26) : 0

  function open(payloadJson) {
    root.opened = true
    root.mode = "emoji"
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "farangkao.emojis-nerd")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function loadEmojis(raw) {
    root.emojis = EmojiSearch.parseEmojis(raw)
    if (root.opened) root.rebuildDisplay()
  }

  function rebuildDisplay() {
    if (root.mode === "nerd") {
      root.selectedIndex = 0
      nerdSearchDebounce.restart()
      return
    }
    if (root.mode === "kaomoji") {
      root.selectedIndex = 0
      // First activation pulls the trigger on the deferred read; an
      // empty return means the file hasn't landed yet and onLoaded
      // will rebuild instead.
      if (root.kaomojiRows === null) {
        var raw = kaomojiFile.text()
        if (raw) root.kaomojiRows = EmojiSearch.parseKaomojiTsv(raw)
      }
      if (root.kaomojiRows === null) return
      fillDisplay(EmojiSearch.filterEmojis(root.kaomojiRows, root.filterText, 1000))
      return
    }
    fillDisplay(EmojiSearch.filterEmojis(root.emojis, root.filterText, 1000))
  }

  function fillDisplay(out) {
    displayModel.clear()
    for (var j = 0; j < out.length; j++) {
      displayModel.append({
        emoji: out[j].e,
        index: j,
        name: (out[j].n || ""),
        tags: EmojiSearch.formatKaomojiTags(out[j].tags)
      })
    }

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0
    cursorActive = displayModel.count > 0

    Qt.callLater(function() {
      if (displayModel.count > 0) root.positionSelected()
    })
  }

  function positionSelected() {
    if (root.mode === "kaomoji") kaomojiList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    else resultGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
  }

  function runNerdSearch() {
    var tokens = EmojiSearch.queryTokens(root.filterText)
    root.nerdSearchSeq++

    var cmd
    if (tokens.length === 0) {
      cmd = ["/usr/bin/head", "-n", "1000", root.tsvPath]
    } else {
      // The longest token is the cheapest grep prefilter; the exact
      // token-AND over keywords runs in JS once the rows arrive.
      tokens.sort(function(a, b) { return b.length - a.length })
      cmd = ["/usr/bin/grep", "-i", "-F", "--", tokens[0], root.tsvPath]
    }

    if (nerdProc.running) {
      root.nerdPendingCmd = cmd
      nerdProc.running = false
      return
    }
    startNerdProc(cmd)
  }

  function startNerdProc(cmd) {
    root.nerdRows = []
    root.nerdActiveTokens = EmojiSearch.queryTokens(root.filterText)
    root.nerdRunningSeq = root.nerdSearchSeq
    nerdProc.command = cmd
    nerdProc.running = true
  }

  function select(delta) {
    if (displayModel.count === 0) return
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    positionSelected()
  }

  // Up/Down step one entry per line in the kaomoji list, one grid row
  // (columns entries) in the pickers.
  function rowStep() {
    return root.mode === "kaomoji" ? 1 : columns
  }

  function selectRow(delta) {
    if (displayModel.count === 0) return
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
      positionSelected()
      return
    }
    var newIndex = selectedIndex + delta * rowStep()
    if (newIndex < 0) newIndex = 0
    if (newIndex >= displayModel.count) newIndex = displayModel.count - 1
    selectedIndex = newIndex
    positionSelected()
  }

  function selectPage(delta) {
    if (displayModel.count === 0) return
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
      positionSelected()
      return
    }
    var viewHeight = root.mode === "kaomoji" ? kaomojiList.height : resultGrid.height
    var rowHeight = root.mode === "kaomoji" ? listRowHeight : cellHeight
    var visibleRows = Math.max(1, Math.floor(viewHeight / rowHeight))
    var newIndex = selectedIndex + delta * rowStep() * visibleRows
    if (newIndex < 0) newIndex = 0
    if (newIndex >= displayModel.count) newIndex = displayModel.count - 1
    selectedIndex = newIndex
    positionSelected()
  }

  function setMode(nextMode) {
    if (root.mode === nextMode) return
    root.mode = nextMode
    // Keep the filter across switches so Tab compares the same query
    // in every dataset.
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
  }

  function setFilter(nextFilter) {
    // A leading "!" is the Nerd Fonts trigger: flip the mode once and
    // keep searching without the marker. The mode is sticky until the
    // user switches back via tabs or the Tab key.
    if (nextFilter.length > 0 && nextFilter.charAt(0) === "!") {
      root.mode = "nerd"
      nextFilter = nextFilter.substring(1)
    }
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
  }

  function activateIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    root.applySelected(row.emoji)
  }

  function copyIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    root.copySelected(row.emoji)
  }

  function applySelected(emoji) {
    if (!emoji) return
    root.dismiss()
    Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-menu-emoji-insert", emoji])
  }

  function copySelected(emoji) {
    if (!emoji) return
    root.dismiss()
    // Plain wl-copy: no --sensitive/--foreground, so the glyph keeps
    // clipboard ownership (stays pasteable) and enters the shell's
    // clipboard history.
    Quickshell.execDetached(["/usr/bin/wl-copy", "--type", "text/plain", emoji])
  }

  ListModel { id: displayModel }

  FileView {
    path: Qt.resolvedUrl("emojis.json")
    onLoaded: root.loadEmojis(text())
  }

  // kaomoji.tsv reads on first tab activation: preload stays false so
  // assigning path never loads; the first text() call then reads the
  // (tiny) file synchronously via blockLoading. onLoaded covers the
  // case where the read still settles asynchronously.
  FileView {
    id: kaomojiFile
    preload: false
    blockLoading: true
    path: Qt.resolvedUrl("kaomoji.tsv")

    onLoaded: {
      root.kaomojiRows = EmojiSearch.parseKaomojiTsv(text())
      if (root.opened && root.mode === "kaomoji") root.rebuildDisplay()
    }
  }

  Timer {
    id: nerdSearchDebounce
    interval: 160
    onTriggered: root.runNerdSearch()
  }

  Process {
    id: nerdProc
    command: ["/usr/bin/true"]

    stdout: SplitParser {
      onRead: function(data) { root.nerdRows.push(data) }
    }

    onExited: function(exitCode) {
      if (root.nerdPendingCmd) {
        // A SIGTERM from a superseded search is still settling; the
        // queued run starts once this exit finishes.
        var cmd = root.nerdPendingCmd
        root.nerdPendingCmd = null
        Qt.callLater(function() { root.startNerdProc(cmd) })
        return
      }
      // Stale results (mode switched away, newer keystrokes, or a kill)
      // are dropped by the sequence check.
      if (root.mode !== "nerd" || root.nerdRunningSeq !== root.nerdSearchSeq) return
      root.fillDisplay(EmojiSearch.filterTsvRows(root.nerdRows, root.nerdActiveTokens, 1000))
      root.nerdRows = []
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-emojis"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Tab) {
            var next = root.modeOrder[(root.modeOrder.indexOf(root.mode) + 1) % root.modeOrder.length]
            root.setMode(next)
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.selectRow(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.selectRow(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.selectPage(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.selectPage(1)
            event.accepted = true
          } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                     && (event.modifiers & Qt.ControlModifier)) {
            // Ctrl+Enter copies to the clipboard instead of typing.
            if (root.cursorActive) {
              root.copyIndex(root.selectedIndex)
            } else if (displayModel.count > 0) {
              root.cursorActive = true
            }
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.cursorActive) root.activateIndex(root.selectedIndex)
            else if (displayModel.count > 0) root.cursorActive = true
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Row {
          id: tabBar
          width: parent.width
          height: root.headerHeight
          spacing: root.contentSpacing

          Repeater {
            model: [
              { key: "emoji", label: "Emojis" },
              { key: "nerd", label: "Nerd Fonts" },
              { key: "kaomoji", label: "Kaomoji" }
            ]

            delegate: Rectangle {
              id: tab

              required property var modelData

              readonly property bool active: root.mode === modelData.key

              height: root.headerHeight
              width: tabLabel.implicitWidth + Style.spacing.controlPaddingX * 2
              radius: root.cornerRadius
              color: active ? root.selectedBackground : "transparent"
              border.width: active ? 0 : 1
              border.color: root.border

              Text {
                id: tabLabel
                anchors.centerIn: parent
                text: tab.modelData.label
                color: tab.active ? root.selectedText : root.foreground
                opacity: tab.active ? 1 : 0.7
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setMode(tab.modelData.key)
              }
            }
          }
        }

        Rectangle {
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          color: "transparent"

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText
                  || (root.mode === "nerd" ? "Search Nerd Fonts…"
                     : root.mode === "kaomoji" ? "Search kaomoji by tag…"
                                               : "Search emojis…  ( ! switches to Nerd Fonts )")
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight * 2 - root.footerHeight - root.contentSpacing * 3

          GridView {
            id: resultGrid
            anchors.fill: parent
            visible: root.mode !== "kaomoji"
            model: displayModel
            clip: true
            cellWidth: root.cellWidth
            cellHeight: root.cellHeight
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              required property int index
              required property string emoji

              readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex

              width: root.cellWidth
              height: root.cellHeight
              radius: root.cornerRadius
              color: hasCursor ? root.selectedBackground : "transparent"

              Text {
                text: parent.emoji
                // Nerd Font glyphs are monochrome outlines that follow the
                // text color (color emojis ignore it), so theme both modes.
                color: hasCursor ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
              }

              MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) {
                  root.cursorActive = true
                  root.selectedIndex = index
                }
                onClicked: function(mouse) {
                  root.cursorActive = true
                  root.selectedIndex = index
                  // Left-click types the glyph; right-click only copies it.
                  if (mouse.button === Qt.RightButton)
                    root.copyIndex(index)
                  else
                    root.activateIndex(index)
                }
              }
            }
          }

          ListView {
            id: kaomojiList
            anchors.fill: parent
            visible: root.mode === "kaomoji"
            model: displayModel
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              id: kaomojiRow

              required property int index
              required property string emoji
              required property string tags

              readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex

              width: kaomojiList.width
              height: root.listRowHeight
              color: hasCursor ? root.selectedBackground : "transparent"

              Text {
                // The kaomoji itself, left-aligned; capped so long ones
                // never reach the centered tag column.
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(parent.width * 0.42, implicitWidth)
                text: kaomojiRow.emoji
                color: kaomojiRow.hasCursor ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                elide: Text.ElideRight
              }

              Text {
                // Tag column pinned to the panel's horizontal center so
                // it lines up across rows; kept visually secondary.
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(parent.width * 0.5, implicitWidth)
                text: kaomojiRow.tags
                color: kaomojiRow.hasCursor ? root.selectedText : root.foreground
                opacity: kaomojiRow.hasCursor ? 0.75 : 0.5
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) {
                  root.cursorActive = true
                  root.selectedIndex = kaomojiRow.index
                }
                onClicked: function(mouse) {
                  root.cursorActive = true
                  root.selectedIndex = kaomojiRow.index
                  if (mouse.button === Qt.RightButton)
                    root.copyIndex(kaomojiRow.index)
                  else
                    root.activateIndex(kaomojiRow.index)
                }
              }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: displayModel.count === 0

            Text {
              text: "󰈉"
              color: root.foreground
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }

            Text {
              text: root.mode === "kaomoji" && root.kaomojiRows === null
                    ? "Loading kaomoji…"
                    : "No matches for “" + root.filterText + "”"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }
          }
        }

        Rectangle {
          width: parent.width
          height: root.footerHeight
          visible: height > 0
          radius: root.cornerRadius
          color: "transparent"

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(8)
            text: {
              if (root.mode !== "nerd" || !root.cursorActive || displayModel.count === 0)
                return ""
              var row = displayModel.get(root.selectedIndex)
              return row && row.name ? row.name + "   " + row.emoji : ""
            }
            color: root.foreground
            opacity: 0.8
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
        }
      }
    }
  }
}
