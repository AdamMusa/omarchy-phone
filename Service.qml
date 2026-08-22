import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var shell: null
  property var manifest: null
  readonly property string pluginDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir)
    : ""
  readonly property string rubyProgram: pluginDir + "/main.rb"
  property string program: ""
  readonly property string effectiveRubyProgram: program !== "" ? program : rubyProgram

  property bool ready: false
  property bool stopping: false
  property string lastError: ""
  property var surfaces: ({})
  property var surfaceOptions: ({})
  property var nodeIndex: ({})
  property var componentDefinitions: ({})
  property int revision: 0
  property int restartDelayMs: 500
  property int eventSequence: 0
  readonly property int maxStringLength: 16384
  readonly property int maxCollectionItems: 256

  property var allowedTypes: ({})
  property var allowedProperties: ({})

  signal effectReceived(string name, var payload)

  function validId(value) {
    return typeof value === "string"
      && value.length > 0
      && value.length <= 128
      && /^[a-zA-Z0-9_.:-]+$/.test(value)
  }

  function plainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
  }

  function boundedValue(value, depth) {
    if (depth > 8) return false
    if (value === null || typeof value === "number" || typeof value === "boolean") return true
    if (typeof value === "string") return value.length <= maxStringLength
    if (Array.isArray(value)) {
      if (value.length > maxCollectionItems) return false
      for (var i = 0; i < value.length; i++) if (!boundedValue(value[i], depth + 1)) return false
      return true
    }
    if (plainObject(value)) {
      var keys = Object.keys(value)
      if (keys.length > maxCollectionItems) return false
      for (var k = 0; k < keys.length; k++) {
        if (keys[k].length > 128 || !boundedValue(value[keys[k]], depth + 1)) return false
      }
      return true
    }
    return false
  }

  function validateNode(node, index, depth, count) {
    if (!plainObject(node) || depth > 32 || count.value >= 2000) return false
    if (!allowedTypes[String(node.type || "")] || !validId(node.id)) return false
    if (index[node.id] !== undefined) return false

    var props = node.props === undefined ? {} : node.props
    if (!plainObject(props)) return false
    var whitelist = allowedProperties[node.type]
    for (var key in props) {
      if (!whitelist[key]) return false
      var value = props[key]
      if (!boundedValue(value, 0)) return false
    }

    var children = node.children === undefined ? [] : node.children
    if (!Array.isArray(children)) return false
    if (!componentDefinitions[node.type].container && children.length !== 0)
      return false
    var subscriptions = node.events === undefined ? [] : node.events
    if (!Array.isArray(subscriptions)) return false
    for (var e = 0; e < subscriptions.length; e++) {
      var eventName = String(subscriptions[e])
      if (eventName !== "mount" && eventName !== "unmount" && componentDefinitions[node.type].events.indexOf(eventName) < 0)
        return false
    }

    index[node.id] = node
    count.value += 1
    for (var i = 0; i < children.length; i++)
      if (!validateNode(children[i], index, depth + 1, count)) return false
    return true
  }

  function validateComponents(components) {
    if (!plainObject(components)) return false
    var names = Object.keys(components)
    if (names.length === 0 || names.length > 256) return false
    var validated = ({})
    for (var i = 0; i < names.length; i++) {
      var name = names[i]
      var definition = components[name]
      if (!/^[a-z][a-z0-9_]*$/.test(name) || !plainObject(definition)) return false
      if (!/^[A-Z][A-Za-z0-9]*\.qml$/.test(String(definition.qml || ""))) return false
      if (!Array.isArray(definition.properties) || !Array.isArray(definition.events)
          || !plainObject(definition.property_map || {}) || !plainObject(definition.event_map || {})) return false
      var propertyMap = ({})
      for (var p = 0; p < definition.properties.length; p++) {
        var propertyName = String(definition.properties[p])
        if (!/^[a-z][a-z0-9_]*$/.test(propertyName)) return false
        propertyMap[propertyName] = true
      }
      validated[name] = {
        qml: definition.qml,
        properties: propertyMap,
        events: definition.events,
        propertyMap: definition.property_map || {},
        eventMap: definition.event_map || {},
        container: definition.container === true,
        autoBind: definition.auto_bind !== false
      }
    }
    componentDefinitions = validated
    return true
  }

  function installRender(message) {
    if (!plainObject(message.surfaces)) return reject("render surfaces must be an object")
    if (message.surface_options !== undefined && !validateSurfaceOptions(message.surface_options))
      return reject("invalid surface options")
    if (!validateComponents(message.components)) return reject("invalid component registry")
    var dynamicTypes = ({})
    var dynamicProperties = ({})
    for (var componentName in componentDefinitions) {
      dynamicTypes[componentName] = true
      dynamicProperties[componentName] = componentDefinitions[componentName].properties
    }
    allowedTypes = dynamicTypes
    allowedProperties = dynamicProperties
    var nextIndex = ({})
    var count = { value: 0 }
    var names = Object.keys(message.surfaces)
    if (names.length === 0 || names.length > 32) return reject("invalid surface count")

    for (var i = 0; i < names.length; i++) {
      if (!validId(names[i]) || !validateNode(message.surfaces[names[i]], nextIndex, 0, count))
        return reject("invalid control tree")
    }

    surfaces = message.surfaces
    surfaceOptions = message.surface_options || ({})
    nodeIndex = nextIndex
    revision += 1
    lastError = ""
  }

  function validateSurfaceOptions(options) {
    if (!plainObject(options)) return false
    var allowed = {
      title: true, width: true, height: true, min_width: true, min_height: true,
      max_width: true, max_height: true, color: true, visible: true,
      maximized: true, fullscreen: true
    }
    for (var surfaceName in options) {
      if (!validId(surfaceName) || !plainObject(options[surfaceName])) return false
      for (var key in options[surfaceName]) {
        if (!allowed[key]) return false
        var value = options[surfaceName][key]
        if (value !== null && typeof value !== "string" && typeof value !== "number" && typeof value !== "boolean")
          return false
      }
    }
    return true
  }

  function applyPatch(message) {
    if (!validId(message.id))
      return reject("invalid patch")
    var node = nodeIndex[message.id]
    if (!node) return reject("patch target rejected")

    if (message.op === "replace_children") {
      if (!componentDefinitions[node.type].container || !Array.isArray(message.children))
        return reject("children patch rejected")
      var removed = ({})
      function markRemoved(child) {
        removed[child.id] = true
        var nested = Array.isArray(child.children) ? child.children : []
        for (var r = 0; r < nested.length; r++) markRemoved(nested[r])
      }
      var oldChildren = Array.isArray(node.children) ? node.children : []
      for (var oldIndex = 0; oldIndex < oldChildren.length; oldIndex++) markRemoved(oldChildren[oldIndex])

      var childrenIndex = ({})
      for (var existingId in nodeIndex)
        if (!removed[existingId] && existingId !== node.id) childrenIndex[existingId] = nodeIndex[existingId]
      var count = { value: Object.keys(childrenIndex).length }
      for (var childIndex = 0; childIndex < message.children.length; childIndex++)
        if (!validateNode(message.children[childIndex], childrenIndex, 0, count)) return reject("invalid children patch")

      var containerReplacement = ({ type: node.type, id: node.id, props: node.props || {}, children: message.children })
      if (node.events !== undefined) containerReplacement.events = node.events
      childrenIndex[node.id] = containerReplacement
      nodeIndex = childrenIndex
      revision += 1
      return true
    }

    if (message.op === "animate") {
      if (!Array.isArray(message.tracks) || message.tracks.length === 0 || message.tracks.length > 64)
        return reject("animation tracks rejected")
      var animatedProps = ({})
      var validatedTracks = []
      var sourceProps = node.props || {}
      for (var trackIndex = 0; trackIndex < message.tracks.length; trackIndex++) {
        var track = message.tracks[trackIndex]
        if (!plainObject(track) || typeof track.property !== "string"
            || !allowedProperties[node.type][track.property] || !validAnimation(track))
          return reject("animation track rejected")
        var targetValue = track.to
        if (targetValue !== null && typeof targetValue !== "string" && typeof targetValue !== "number")
          return reject("animation target rejected")
        animatedProps[track.property] = targetValue
        validatedTracks.push(track)
      }
      var animatedReplacement = ({ type: node.type, id: node.id })
      var finalProps = ({})
      for (var sourceKey in sourceProps) finalProps[sourceKey] = sourceProps[sourceKey]
      for (var animatedKey in animatedProps) finalProps[animatedKey] = animatedProps[animatedKey]
      animatedReplacement.props = finalProps
      if (node.children !== undefined) animatedReplacement.children = node.children
      if (node.events !== undefined) animatedReplacement.events = node.events
      animatedReplacement.transitions = validatedTracks
      var animatedIndex = ({})
      for (var animatedId in nodeIndex) animatedIndex[animatedId] = nodeIndex[animatedId]
      animatedIndex[node.id] = animatedReplacement
      nodeIndex = animatedIndex
      revision += 1
      return true
    }

    if (message.op !== "set" || typeof message.property !== "string") return reject("invalid patch")
    if (!allowedProperties[node.type][message.property]) return reject("patch target rejected")
    var value = message.value
    if (!boundedValue(value, 0)) return reject("patch value rejected")

    var animation = message.animation
    if (animation !== undefined && !validAnimation(animation)) return reject("patch animation rejected")

    var replacement = ({ type: node.type, id: node.id })
    var props = ({})
    var oldProps = node.props || {}
    for (var key in oldProps) props[key] = oldProps[key]
    props[message.property] = value
    replacement.props = props
    if (node.children !== undefined) replacement.children = node.children
    if (node.events !== undefined) replacement.events = node.events
    if (animation !== undefined) {
      replacement.transition = {
        property: message.property,
        from: oldProps[message.property],
        to: value,
        duration: animation.duration,
        delay: animation.delay,
        easing: animation.easing,
        sequence: revision + 1
      }
    }

    var nextIndex = ({})
    for (var id in nodeIndex) nextIndex[id] = nodeIndex[id]
    nextIndex[node.id] = replacement
    nodeIndex = nextIndex
    revision += 1
  }

  function validAnimation(animation) {
    if (!plainObject(animation)
        || typeof animation.duration !== "number" || animation.duration < 0 || animation.duration > 60000
        || typeof animation.delay !== "number" || animation.delay < 0 || animation.delay > 60000
        || typeof animation.easing !== "string") return false
    var easings = ["linear", "in_quad", "out_quad", "in_out_quad", "in_cubic", "out_cubic", "in_out_cubic",
      "in_back", "out_back", "in_out_back", "in_elastic", "out_elastic", "in_out_elastic",
      "in_bounce", "out_bounce", "in_out_bounce"]
    return easings.indexOf(animation.easing) >= 0
  }

  function handleLine(line) {
    var raw = String(line || "").trim()
    if (raw === "" || raw.length > 1048576) return reject("invalid message size")

    var message
    try { message = JSON.parse(raw) }
    catch (error) { return reject("invalid JSON from Ruby") }
    if (!plainObject(message) || message.v !== 1 || typeof message.type !== "string")
      return reject("invalid protocol envelope")

    if (message.type === "ready") {
      ready = true
      restartDelayMs = 500
      lastError = ""
    } else if (message.type === "render") {
      installRender(message)
    } else if (message.type === "patch") {
      applyPatch(message)
    } else if (message.type === "effect") {
      handleEffect(message)
    } else if (message.type === "ack") {
      // Acknowledgements are consumed by benchmarks and future diagnostics.
    } else if (message.type === "handler_error" || message.type === "runtime_error" || message.type === "protocol_error") {
      lastError = String(message.message || message.code || "Ruby runtime error").slice(0, 512)
    } else {
      reject("unknown message type")
    }
  }

  function handleEffect(message) {
    if (typeof message.name !== "string" || message.name.length > 64
        || !plainObject(message.payload || {}) || !boundedValue(message.payload || {}, 0))
      return reject("invalid effect")
    var payload = message.payload || {}
    effectReceived(message.name, payload)
    if (!shell || !manifest) return
    if (message.name === "open_panel")
      shell.summon(manifest.id, JSON.stringify(payload))
    else if (message.name === "close_panel")
      shell.hide(manifest.id)
    else
      reject("effect not allowed")
  }

  function reject(reason) {
    lastError = String(reason || "protocol error").slice(0, 512)
    console.warn("omarchy-ui bridge:", lastError)
    return false
  }

  function rootId(surfaceName) {
    var surface = surfaces[String(surfaceName || "")]
    return surface && validId(surface.id) ? surface.id : ""
  }

  function optionsFor(surfaceName) {
    var options = surfaceOptions[String(surfaceName || "")]
    return plainObject(options) ? options : ({})
  }

  function nodeFor(controlId) {
    return nodeIndex[String(controlId || "")] || null
  }

  function componentSource(typeName) {
    var definition = componentDefinitions[String(typeName || "")]
    return definition ? pluginDir + "/Components/" + definition.qml : ""
  }

  function componentDefinition(typeName) {
    return componentDefinitions[String(typeName || "")] || null
  }

  function sendEvent(surfaceName, controlId, eventName, payload) {
    if (!rubyProcess.running || !validId(controlId) || !/^[a-z][a-z0-9_]{0,63}$/.test(eventName)
        || !plainObject(payload || {}) || !boundedValue(payload || {}, 0)) return false
    var target = nodeIndex[String(controlId)]
    var definition = target ? componentDefinitions[String(target.type)] : null
    var subscriptions = target && Array.isArray(target.events) ? target.events : []
    if (!definition || subscriptions.indexOf(eventName) < 0) return false
    eventSequence += 1
    rubyProcess.write(JSON.stringify({
      v: 1,
      type: "event",
      surface: String(surfaceName || ""),
      id: String(controlId),
      event: eventName,
      seq: eventSequence,
      payload: plainObject(payload) ? payload : {}
    }) + "\n")
    return true
  }

  function startRuby() {
    if (stopping || pluginDir === "" || rubyProcess.running) return
    var configuredRuntime = String(Quickshell.env("OMARCHY_UI_RUNTIME") || "")
    rubyProcess.command = [
      configuredRuntime !== "" ? configuredRuntime : pluginDir + "/omarchy-ui-runtime",
      effectiveRubyProgram
    ]
    rubyProcess.workingDirectory = pluginDir
    rubyProcess.running = true
  }

  onPluginDirChanged: Qt.callLater(startRuby)

  Component.onDestruction: {
    stopping = true
    restartTimer.stop()
    if (rubyProcess.running) rubyProcess.running = false
  }

  Process {
    id: rubyProcess
    stdinEnabled: true

    stdout: SplitParser {
      onRead: function(line) { root.handleLine(line) }
    }

    stderr: SplitParser {
      onRead: function(line) {
        var message = String(line || "").trim()
        if (message !== "") console.warn("omarchy-ui ruby:", message)
      }
    }

    onExited: function(exitCode) {
      root.ready = false
      if (root.stopping || root.pluginDir === "") return
      root.lastError = exitCode === 0
        ? "Ruby UI runtime stopped"
        : "Ruby UI runtime crashed (exit " + exitCode + ")"
      restartTimer.interval = root.restartDelayMs
      restartTimer.start()
      root.restartDelayMs = Math.min(30000, root.restartDelayMs * 2)
    }
  }

  Timer {
    interval: 100
    repeat: true
    running: rubyProcess.running
    onTriggered: rubyProcess.write('{"v":1,"type":"tick"}\n')
  }

  Timer {
    id: restartTimer
    interval: 500
    repeat: false
    onTriggered: root.startRuby()
  }
}
