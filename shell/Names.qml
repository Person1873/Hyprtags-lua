import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Tag names. A popout under the tags widget with one field per tag; a name replaces the
// number in the bar. Names live in the widget's own entry in ~/.config/omarchy/shell.json
// (`names: { "3": "web" }`), written through the shell's setBarWidget IPC, the same path as
// `omarchy bar set person1873.hypr-dwm-land names '{...}' --json`. Any Unicode; up to 24
// characters; an empty field restores the number.
Panel {
  id: root
  moduleName: "person1873.hypr-dwm-land"
  ipcTarget: "person1873.hypr-dwm-land"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  property int ntags: 21
  readonly property int maxLength: 24
  // The names come from shell.json itself, watched, not from the settings object handed
  // to this pane: that copy went stale after the first change and every later save
  // merged into it, so a rename snapped back and old names came back on other tags.
  readonly property string shellJson: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy/shell.json"
  property var names: ({})

  function readNames(text) {
    try {
      var cfg = JSON.parse(text || "{}")
      var layout = (cfg.bar && cfg.bar.layout) || {}
      for (var section in layout) {
        var entries = layout[section]
        if (!Array.isArray(entries)) continue
        for (var i = 0; i < entries.length; i++) {
          var e = entries[i]
          if (e && e.id === root.moduleName) return (e.names && typeof e.names === "object") ? e.names : {}
        }
      }
    } catch (err) {}
    return {}
  }

  FileView {
    id: shellFile
    path: root.shellJson
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.names = root.readNames(text())
    onLoadFailed: root.names = ({})
  }

  property var fields: []
  property bool editing: false

  function open() {
    shellFile.reload()
    root.controller.show()
    // land in the first field: Tab / Shift+Tab walk the fields, Return saves, Escape closes
    Qt.callLater(function() { if (root.opened && fields.length > 0) fields[0].forceActiveFocus() })
  }
  function openFromHotkey() { open() }
  function close() { root.controller.hide() }
  function toggle() { opened ? close() : open() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function defaultLabel(k) { return k > 9 ? "F" + (k - 9) : String(k) }

  function save(k, text) {
    var value = String(text || "").trim().substring(0, maxLength)
    var current = names[String(k)] || ""
    if (value === current) return
    var next = {}
    for (var key in names) if (names[key]) next[key] = names[key]
    if (value) next[String(k)] = value
    else delete next[String(k)]
    // argv, not a shell line: the name is user text.
    setProc.command = ["omarchy-shell", "shell", "setBarWidget", root.moduleName, "names", JSON.stringify(next), "{}"]
    setProc.running = true
  }

  Process {
    id: setProc
    command: ["true"]
    stdout: StdioCollector {
      onStreamFinished: {
        var out = String(text || "").trim()
        if (out && out !== "ok") console.warn("hypr-dwm-land names: " + out)
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editing
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: column
          width: parent.width
          spacing: Style.space(6)

          Text {
            text: "Tag names"
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Text {
            width: parent.width
            text: "A name replaces the number in the bar. Empty means the number."
            color: Qt.darker(root.barForeground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          PanelSeparator { width: parent.width; foreground: root.barForeground }

          Repeater {
            model: root.ntags
            RowLayout {
              required property int index
              readonly property int tag: index + 1
              width: column.width
              spacing: Style.space(8)

              Text {
                Layout.preferredWidth: Style.space(28)
                text: root.defaultLabel(tag)
                color: root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignRight
              }
              TextField {
                id: field
                Layout.fillWidth: true
                foreground: root.barForeground
                text: root.names[String(tag)] || ""
                placeholderText: root.defaultLabel(tag)
                maximumLength: root.maxLength
                onAccepted: root.save(tag, text)
                onEditingFinished: root.save(tag, text)
                onActiveFocusChanged: if (activeFocus) root.editing = true; else Qt.callLater(function() { root.editing = root.fields.some(function(f) { return f.activeFocus }) })
                Keys.onEscapePressed: root.close()
                Keys.onTabPressed: { var i = root.fields.indexOf(field); if (i >= 0) root.fields[(i + 1) % root.fields.length].forceActiveFocus() }
                Keys.onBacktabPressed: { var i = root.fields.indexOf(field); if (i >= 0) root.fields[(i - 1 + root.fields.length) % root.fields.length].forceActiveFocus() }
                Component.onCompleted: { var list = root.fields.slice(); list[tag - 1] = field; root.fields = list }
                // a change made elsewhere (CLI, another monitor's bar) while not editing
                Connections {
                  target: root
                  function onNamesChanged() { if (!field.activeFocus) field.text = root.names[String(tag)] || "" }
                }
              }
            }
          }
        }
      }
    }
  }
}
