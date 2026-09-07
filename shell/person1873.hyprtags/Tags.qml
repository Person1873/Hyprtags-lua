import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// DWM-style tag bar. State comes from the hyprtags Lua module over Hyprland's socket2 as
//   custom>>hyprtags>><monitor>|v=<viewed>|o=<tag:count,...>|u=<urgent tags>|f=<focused tags>
// Clicks go back through `hyprctl eval`.
//   left        view tag        right       toggle tag into the view
//   ctrl+left   tag window      ctrl+right  toggle window tag
BarWidget {
  id: root
  moduleName: "person1873.hyprtags"

  property int ntags: Number(setting("ntags", 21))
  property string monitorName: ""
  property var viewed: ({})
  property var occupied: ({})
  property var urgentTags: ({})
  property var focusedTags: ({})
  property var tags: []

  // Which Hyprland monitor this bar surface sits on. The bar window is assigned after
  // creation, so resolve lazily and retry.
  function resolveMonitor() {
    if (monitorName !== "") return true
    var win = root.QsWindow ? root.QsWindow.window : null
    var screen = win ? win.screen : null
    var mon = screen ? Hyprland.monitorFor(screen) : null
    if (mon && mon.name) monitorName = String(mon.name)
    return monitorName !== ""
  }

  function parseSet(s) {
    var out = {}
    if (!s) return out
    var parts = s.split(",")
    for (var i = 0; i < parts.length; i++) {
      var p = parts[i]
      if (p === "") continue
      var kv = p.split(":")
      out[Number(kv[0])] = kv.length > 1 ? Number(kv[1]) : true
    }
    return out
  }

  function apply(line) {
    var fields = line.split("|")
    if (fields.length < 1) return
    var mon = fields[0]
    if (!resolveMonitor()) {
      // Unknown yet: accept only when there is a single monitor.
      if (Hyprland.monitors.values.length > 1) return
    } else if (mon !== monitorName) {
      return
    }
    var v = {}, o = {}, u = {}, f = {}
    for (var i = 1; i < fields.length; i++) {
      var eq = fields[i].indexOf("=")
      if (eq < 0) continue
      var key = fields[i].substring(0, eq)
      var val = fields[i].substring(eq + 1)
      if (key === "v") v = parseSet(val)
      else if (key === "o") o = parseSet(val)
      else if (key === "u") u = parseSet(val)
      else if (key === "f") f = parseSet(val)
    }
    viewed = v; occupied = o; urgentTags = u; focusedTags = f
    var list = []
    for (var k = 1; k <= ntags; k++) {
      if (v[k] || o[k]) list.push(k)
    }
    tags = list
  }

  function call(expr) {
    if (!root.bar) return
    root.bar.run("hyprctl eval " + Util.shellQuote(expr))
  }

  function request() {
    resolveMonitor()
    call("hyprtags.emit()")
  }

  function monArg() {
    return monitorName !== "" ? ", \"" + monitorName + "\"" : ""
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "custom") {
        var d = String(event.data)
        if (d.indexOf("hyprtags>>") === 0) root.apply(d.substring(10))
      } else if (event.name === "configreloaded") {
        retry.restart()
      }
    }
  }

  Timer {
    id: retry
    interval: 250
    repeat: false
    onTriggered: root.request()
  }

  // Ask again a few times at startup: the shell may come up before Hyprland has run init.
  Timer {
    id: warmup
    interval: 1500
    repeat: true
    property int left: 4
    onTriggered: {
      root.request()
      if (--left <= 0) stop()
    }
  }

  Component.onCompleted: { retry.start(); warmup.start() }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : Math.max(1, root.tags.length)
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.tags

      Item {
        id: cell
        required property int modelData

        readonly property bool isViewed: root.viewed[modelData] === true
        readonly property bool isOccupied: root.occupied[modelData] !== undefined
        readonly property bool isUrgent: root.urgentTags[modelData] === true
        readonly property bool hasFocus: root.focusedTags[modelData] === true

        implicitWidth: button.implicitWidth
        implicitHeight: button.implicitHeight

        WidgetButton {
          id: button
          anchors.fill: parent
          bar: root.bar
          pressable: false
          // tags 10..21 live on F1..F12, so label them that way
          text: cell.hasFocus ? "󱓻" : (cell.modelData > 9 ? "F" + (cell.modelData - 9) : String(cell.modelData))
          active: cell.isUrgent
          opacity: cell.isOccupied || cell.isViewed ? 1 : 0.5
          horizontalMargin: 6
          verticalPadding: 6
          fixedWidth: root.vertical ? root.barSize : Style.space(20)
          fixedHeight: root.barSize
          tooltipText: "Tag " + cell.modelData + (cell.isOccupied ? " (" + root.occupied[cell.modelData] + ")" : "")
        }

        // Viewed-tag marker, dwm style: a thin bar along the outer edge.
        Rectangle {
          visible: cell.isViewed
          color: button.foreground
          opacity: 0.9
          radius: 1
          height: root.vertical ? parent.height - 8 : 2
          width: root.vertical ? 2 : parent.width - 10
          anchors.horizontalCenter: root.vertical ? undefined : parent.horizontalCenter
          anchors.verticalCenter: root.vertical ? parent.verticalCenter : undefined
          anchors.bottom: root.vertical ? undefined : parent.bottom
          anchors.bottomMargin: root.vertical ? 0 : 3
          anchors.left: root.vertical ? parent.left : undefined
          anchors.leftMargin: root.vertical ? 3 : 0
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: Qt.PointingHandCursor
          onClicked: function(mouse) {
            var ctrl = (mouse.modifiers & Qt.ControlModifier) !== 0
            var k = cell.modelData
            if (mouse.button === Qt.LeftButton && !ctrl) root.call("hyprtags.view(" + k + root.monArg() + ")")
            else if (mouse.button === Qt.RightButton && !ctrl) root.call("hyprtags.toggleview(" + k + root.monArg() + ")")
            else if (mouse.button === Qt.LeftButton && ctrl) root.call("hyprtags.tag(" + k + ")")
            else if (mouse.button === Qt.RightButton && ctrl) root.call("hyprtags.toggletag(" + k + ")")
          }
        }
      }
    }
  }
}
