import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  property var manifest: null
  moduleName: manifest ? String(manifest.id) : ""

  readonly property var rubyService: bar && bar.shell
    ? bar.shell.serviceFor(moduleName)
    : null
  readonly property string surfaceName: "bar"
  readonly property string rootControlId: rubyService ? rubyService.rootId(surfaceName) : ""

  implicitWidth: Math.max(Style.bar.iconSlot, renderer.implicitWidth + Style.space(12))
  implicitHeight: barSize

  ControlNode {
    id: renderer
    anchors.centerIn: parent
    visible: root.rubyService && root.rootControlId !== ""
    bridge: root.rubyService
    surfaceName: root.surfaceName
    controlId: root.rootControlId
    foreground: root.bar ? root.bar.barForeground : Color.foreground
    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  }

  Text {
    anchors.centerIn: parent
    visible: !renderer.visible
    text: root.rubyService && root.rubyService.lastError !== "" ? "!rb" : "rb"
    color: root.bar ? root.bar.barForeground : Color.foreground
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      if (root.rubyService && root.rootControlId !== "")
        root.rubyService.sendEvent(root.surfaceName, root.rootControlId, "click", {})
    }
  }
}
