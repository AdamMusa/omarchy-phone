# frozen_string_literal: true

require "omarchy_ui"
require_relative "lib/phone_backend"

backend = PhoneBackend.new
last_auto_connect_at = 0

OmarchyUI.plugin do
  state :devices, []
  state :backends, {}
  state :message, "Starting phone discovery…"
  state :audio, true
  state :screen_off, false
  state :fullscreen, false
  state :max_size, 1920
  state :max_fps, 60
  state :bitrate_mbps, 8
  state :pair_address, ""
  state :pair_code, ""

  refresh = proc do
    snapshot = backend.snapshot
    connected_android = snapshot.fetch(:devices).any? do |device|
      device.fetch(:platform) == "Android" && device.fetch(:connected)
    end
    if !connected_android && Time.now.to_i - last_auto_connect_at >= 15
      last_auto_connect_at = Time.now.to_i
      address = backend.last_android_address
      unless address.empty?
        backend.connect(address)
        snapshot = backend.snapshot
      end
    end
    transaction do
      state.devices = snapshot.fetch(:devices)
      state.backends = snapshot.fetch(:backends)
      state.message = state.devices.empty? ? "No phones found" : "#{state.devices.count} phone(s) found"
    end
  rescue StandardError => error
    state.message = error.message
  end

  notify_result = proc do |result|
    state.message = result.message
    urgency = result.ok ? "normal" : "critical"
    run_command(["omarchy", "notification", "send", "-u", urgency, "Omarchy Phone", result.message], timeout: 5)
  rescue StandardError
    nil
  end

  bar_widget do
    row spacing: 6 do
      icon :phone, size: 14, color: "#7dcfff"
      text "PHONE", style: :caption, color: "#7dcfff"
      text(id: :phone_summary) do
        state.devices.empty? ? "Phone" : state.devices.first.fetch(:name, "Phone")
      end
    end
    on_click { open_panel :phone }
  end

  panel :phone do
    scroll width: 660, height: 780 do
      column spacing: 16 do
        column spacing: 2 do
          status = text "", id: :status, style: :caption, width: 610
          bind(status, :text) { state.message }
          row spacing: 9 do
            text "Omarchy", size: 30, bold: true
            icon :phone, size: 22, color: "#7dcfff"
            text "Phone", size: 30, bold: true, width: 430
            action_button :refresh, tooltip: "Rediscover phones", foreground: "#7dcfff" do
              async(&refresh)
            end
          end
        end

        separator
        dynamic id: :transport_map, spacing: 10 do
          android = state.backends[:android] || state.backends["android"] || {}
          ios = state.backends[:ios] || state.backends["ios"] || {}
          adb_ready = android[:adb] || android["adb"]
          scrcpy_ready = android[:scrcpy] || android["scrcpy"]
          ios_ready = ios[:libimobiledevice] || ios["libimobiledevice"]
          airplay_ready = ios[:airplay] || ios["airplay"]
          android_color = adb_ready && scrcpy_ready ? "#d8ff73" : "#ff8b8b"
          ios_color = ios_ready && airplay_ready ? "#d8ff73" : "#f0bd6a"

          row spacing: 0 do
            column spacing: 2 do
              text "ANDROID", style: :caption, color: android_color
              text "●━━━━━━━━━━━━", size: 17, color: android_color
            end
            column spacing: 2 do
              text "WIRELESS / USB", style: :caption, color: "#829088"
              text "━━━━━━◆━━━━━━", size: 17, color: "#7dcfff"
            end
            column spacing: 2 do
              text "IPHONE", style: :caption, color: ios_color
              text "━━━━━━━━━━━━●", size: 17, color: ios_color
            end
          end
          row spacing: 28 do
            text "ADB #{adb_ready ? 'READY' : 'MISSING'}", style: :caption, color: android_color
            text "SCRCPY #{scrcpy_ready ? 'READY' : 'MISSING'}", style: :caption, color: android_color
            text "DEVICE LINK #{ios_ready ? 'READY' : 'MISSING'}", style: :caption, color: ios_color
            text "AIRPLAY #{airplay_ready ? 'READY' : 'MISSING'}", style: :caption, color: ios_color
          end
        end

        separator
        row spacing: 10 do
          text "DEVICE DOCK", size: 12, bold: true, color: "#7dcfff", width: 480
          text "LIVE DISCOVERY", style: :caption, color: "#829088"
        end

        dynamic id: :devices, spacing: 12 do
          if state.devices.empty?
            column spacing: 3 do
              text "        ╭──────────╮", color: "#829088"
              text "        │          │", color: "#829088"
              text "        │    ○     │", size: 18, color: "#7dcfff"
              text "        │          │", color: "#829088"
              text "        ╰────○─────╯", color: "#829088"
              text "No phone is on the dock", size: 20, bold: true
              text "Enable Android Wireless Debugging, or connect and trust an iPhone.",
                   style: :caption, width: 560, wrap: true
            end
          else
            state.devices.each_with_index do |device, index|
              safe_id = device.fetch(:id).gsub(/[^a-zA-Z0-9_.:-]/, "_")
              device_color = device.fetch(:connected) ? "#d8ff73" : "#7dcfff"
              platform_icon = device.fetch(:platform) == "iOS" ? "\uf179" : "\uf17b"
              connection_label = device.fetch(:connected) ? "CONNECTED" : "AVAILABLE"
              row spacing: 16 do
                column spacing: 0 do
                  text "╭────────╮", color: device_color
                  text "│   #{device.fetch(:connected) ? '●' : '○'}    │", color: device_color
                  text "│        │", color: device_color
                  text "│        │", color: device_color
                  text "╰───○────╯", color: device_color
                end
                column spacing: 5 do
                  row spacing: 8 do
                    text (index + 1).to_s.rjust(2, "0"), style: :caption, color: device_color, width: 24
                    icon platform_icon, color: device_color
                    text device.fetch(:name), size: 19, bold: true, width: 320
                    text connection_label, style: :caption, color: device_color
                  end
                  text "#{device.fetch(:platform).upcase}  ·  #{device.fetch(:transport).upcase}",
                       style: :caption, color: "#829088"
                  text "●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●", style: :caption, color: device_color
                  text device.fetch(:capabilities).map { |name, status| "#{name}: #{status}" }.join(" · "),
                       style: :caption, width: 470, wrap: true
                  row spacing: 7 do
                    if device.fetch(:connected)
                      button(device.fetch(:platform) == "iOS" ? "Mirror" : "Open Phone", id: "open.#{safe_id}", accent: device_color) do
                        options = {
                          audio: state.audio, screen_off: state.screen_off, fullscreen: state.fullscreen,
                          max_size: state.max_size, max_fps: state.max_fps, bitrate_mbps: state.bitrate_mbps
                        }
                        async { notify_result.call(backend.open(device.transform_keys(&:to_s), options)) }
                      end
                      if device.fetch(:platform) == "Android"
                        button("Disconnect", id: "disconnect.#{safe_id}") do
                          async { notify_result.call(backend.disconnect(device.fetch(:id))); refresh.call }
                        end
                      end
                    elsif device.fetch(:platform) == "Android"
                      button("Connect", id: "connect.#{safe_id}", accent: device_color) do
                        async do
                          result = backend.connect(device.fetch(:id))
                          if result.ok
                            connected = backend.snapshot.fetch(:devices).find do |candidate|
                              candidate.fetch(:platform) == "Android" && candidate.fetch(:connected)
                            end
                            options = {
                              audio: state.audio, screen_off: state.screen_off, fullscreen: state.fullscreen,
                              max_size: state.max_size, max_fps: state.max_fps, bitrate_mbps: state.bitrate_mbps
                            }
                            result = backend.open(connected.transform_keys(&:to_s), options) if connected
                          end
                          notify_result.call(result)
                          refresh.call
                        end
                      end
                    end
                    if device.fetch(:platform) == "iOS"
                      button("Trust", id: "trust.#{safe_id}") do
                        async { notify_result.call(backend.trust_iphone(device.fetch(:id))); refresh.call }
                      end
                    elsif device.fetch(:platform) == "Android"
                      button("Forget", id: "forget.#{safe_id}") do
                        async { notify_result.call(backend.forget(device.fetch(:id))); refresh.call }
                      end
                    end
                  end
                end
              end
              separator unless index == state.devices.length - 1
            end
          end
        end

        separator
        text "ANDROID MIRROR SIGNAL", size: 12, bold: true, color: "#7dcfff"
        text "PHONE  ●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◆  DESKTOP",
             style: :caption, color: "#7dcfff"
        row spacing: 18 do
          audio_toggle = toggle("Audio", checked: state.audio, id: :audio) { |event| state.audio = event.fetch("value") }
          bind(audio_toggle, :checked) { state.audio }
          screen_toggle = toggle("Screen off", checked: state.screen_off, id: :screen_off) { |event| state.screen_off = event.fetch("value") }
          bind(screen_toggle, :checked) { state.screen_off }
          fullscreen_toggle = toggle("Fullscreen", checked: state.fullscreen, id: :fullscreen) { |event| state.fullscreen = event.fetch("value") }
          bind(fullscreen_toggle, :checked) { state.fullscreen }
        end
        row spacing: 12 do
          size_field = number_field(state.max_size, id: :max_size, label: "Resolution", from: 0, to: 7680, step: 160) { |event| state.max_size = event.fetch("value") }
          bind(size_field, :value) { state.max_size }
          fps_field = number_field(state.max_fps, id: :max_fps, label: "FPS", from: 1, to: 240, step: 5) { |event| state.max_fps = event.fetch("value") }
          bind(fps_field, :value) { state.max_fps }
          bitrate_field = number_field(state.bitrate_mbps, id: :bitrate, label: "Mbps", from: 1, to: 100) { |event| state.bitrate_mbps = event.fetch("value") }
          bind(bitrate_field, :value) { state.bitrate_mbps }
        end

        dynamic id: :android_setup, spacing: 8 do
          if state.devices.none? { |device| device.fetch(:platform) == "Android" && device.fetch(:connected) }
            separator
            text "PAIRING BEAM", size: 12, bold: true, color: "#d8ff73"
            text "ANDROID  ○━━━━━━━━━━━━━━ enter the temporary endpoint and code ━━━━━━━━━━━━━━◆  OMARCHY",
                 style: :caption, color: "#829088", width: 610, wrap: true
            row spacing: 8 do
              column spacing: 4 do
                text "PAIRING IP + PORT", style: :caption, color: "#d8ff73"
                address_field = text_field "", id: :pair_address, placeholder: "192.168.1.20:37123" do |event|
                  state.pair_address = event.fetch("value")
                end
                bind(address_field, :text) { state.pair_address }
              end
              column spacing: 4 do
                text "SIX-DIGIT CODE", style: :caption, color: "#d8ff73"
                text_field "", id: :pair_code, placeholder: "123456" do |event|
                  state.pair_code = event.fetch("value")
                end
              end
              column spacing: 4 do
                text "LINK", style: :caption, color: "#d8ff73"
                button "Pair", id: :pair, accent: "#d8ff73" do
                  async do
                    result = backend.pair_android(state.pair_address, state.pair_code)
                    notify_result.call(result)
                    refresh.call
                  end
                end
              end
            end
          end
        end

        separator
        row spacing: 10 do
          column spacing: 2 do
            text "AIRPLAY RECEIVER", size: 12, bold: true, color: "#7dcfff"
            text "IPHONE  ●━━━━━━━━━━━━━━━━━━━━━━◆  OMARCHY", style: :caption, color: "#7dcfff"
          end
          button "Start AirPlay", id: :airplay_start, accent: "#7dcfff" do
            async { notify_result.call(backend.start_airplay(fullscreen: state.fullscreen)) }
          end
          button "Stop", id: :airplay_stop do
            async { notify_result.call(backend.stop_airplay) }
          end
        end
      end
    end
  end

  after(0.05, &refresh)
  every(5, &refresh)
end
