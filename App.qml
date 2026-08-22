import QtQuick
import Quickshell
import qs.Commons
import qs.Ui as OmarchyUi

ShellRoot {
  id: root

  readonly property string configuredProjectDir: String(Quickshell.env("OMARCHY_UI_PROJECT_DIR") || "")
  readonly property string projectDir: configuredProjectDir !== "" ? configuredProjectDir : Quickshell.shellDir
  readonly property string requestedProgram: Quickshell.env("OMARCHY_UI_RUBY_PROGRAM")
  readonly property var appManifest: ({
    id: "omarchy-ui-application",
    name: "Omarchy UI",
    __sourceDir: projectDir
  })
  property bool wasMapped: false
  readonly property string activeSurface: applicationSurface()
  readonly property var windowOptions: service.optionsFor(activeSurface)

  function option(name, fallback) {
    var value = windowOptions ? windowOptions[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function applicationSurface() {
    if (!service || !service.surfaces) return ""
    if (service.rootId("main") !== "") return "main"
    var names = Object.keys(service.surfaces)
    for (var i = 0; i < names.length; i++)
      if (names[i] !== "bar") return names[i]
    return names.length > 0 ? names[0] : ""
  }

  Service {
    id: service
    manifest: root.appManifest
    program: root.requestedProgram
  }

  FloatingWindow {
    id: window
    visible: root.option("visible", true) !== false
    title: String(root.option("title", root.appManifest.name))
    implicitWidth: Number(root.option("width", 760))
    implicitHeight: Number(root.option("height", 520))
    minimumSize: Qt.size(Number(root.option("min_width", 320)), Number(root.option("min_height", 220)))
    maximumSize: Qt.size(Number(root.option("max_width", 16777215)), Number(root.option("max_height", 16777215)))
    maximized: root.option("maximized", false) === true
    fullscreen: root.option("fullscreen", false) === true
    color: root.option("color", Color.popups.background)

    onBackingWindowVisibleChanged: {
      if (backingWindowVisible) root.wasMapped = true
      else if (root.wasMapped) Qt.quit()
    }

    Rectangle {
      anchors.fill: parent
      color: window.color

      Rectangle {
        id: titleBar
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: Style.space(44)
        color: Color.popups.background

        Text {
          anchors { left: parent.left; leftMargin: Style.space(16); verticalCenter: parent.verticalCenter }
          text: window.title
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton
          onPressed: window.startSystemMove()
          onDoubleClicked: window.maximized = !window.maximized
        }
      }

      ControlNode {
        id: renderer
        anchors {
          left: parent.left
          right: parent.right
          top: titleBar.bottom
          bottom: parent.bottom
          margins: Style.space(24)
        }
        visible: root.activeSurface !== "" && service.rootId(root.activeSurface) !== ""
        bridge: service
        surfaceName: root.activeSurface
        controlId: service.rootId(surfaceName)
        foreground: Color.foreground
        fontFamily: Style.font.family
      }

      Text {
        anchors.centerIn: parent
        visible: !renderer.visible
        text: service.lastError !== "" ? service.lastError : "Starting Ruby UI…"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }
  }
}
