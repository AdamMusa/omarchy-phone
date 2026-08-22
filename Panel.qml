import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui as OmarchyUi

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null
  property bool opened: false
  property string surfaceName: "counter"

  readonly property string rootControlId: service ? service.rootId(surfaceName) : ""

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} }
    catch (error) { payload = {} }
    if (typeof payload.surface === "string" && payload.surface !== "")
      surfaceName = payload.surface
    opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    opened = false
  }

  function dismiss() {
    if (shell && manifest) shell.hide(manifest.id)
    else close()
  }

  PanelWindow {
    id: window
    visible: root.opened
    anchors { top: true; right: true; bottom: true; left: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-ruby-ui-poc"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.62)

      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.dismiss()

      OmarchyUi.BorderSurface {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.space(32), Math.max(Style.space(320), renderer.implicitWidth + Style.space(48)))
        height: Math.min(parent.height - Style.space(32), Math.max(Style.space(180), renderer.implicitHeight + Style.space(48)))
        color: Color.popups.background
        borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Math.max(1, Style.normalBorderWidth))
        radius: Style.cornerRadius

        MouseArea {
          anchors.fill: parent
          onClicked: {}
        }

        ControlNode {
          id: renderer
          anchors.centerIn: parent
          visible: root.service && root.rootControlId !== ""
          bridge: root.service
          surfaceName: root.surfaceName
          controlId: root.rootControlId
          foreground: Color.foreground
          fontFamily: Style.font.family
        }

        Column {
          anchors.centerIn: parent
          spacing: Style.space(8)
          visible: !renderer.visible

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.service && root.service.lastError !== ""
              ? root.service.lastError
              : "Starting Ruby UI…"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }
      }
    }
  }
}
