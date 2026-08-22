# frozen_string_literal: true

require_relative "../../lib/omarchy_ui" unless Object.const_defined?(:OmarchyUI)
unless Object.const_defined?(:PhoneBackend)
  backend_path = File.join(File.dirname(__FILE__), "lib", "phone_backend.rb")
  eval(File.read(backend_path))
end

backend = PhoneBackend.new

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
    row spacing: 7 do
      icon :phone
      text(id: :phone_summary) do
        state.devices.empty? ? "Phone" : state.devices.first.fetch(:name, "Phone")
      end
    end
    on_click { open_panel :phone }
  end

  panel :phone do
    scroll width: 570, height: 680 do
      column spacing: 12 do
      row spacing: 10 do
        text "Phone", style: :heading
        status = text "", id: :status, style: :caption
        bind(status, :text) { state.message }
        button "Refresh", id: :refresh do
          async(&refresh)
        end
      end

      separator

      dynamic id: :devices, spacing: 10 do
        if state.devices.empty?
          text "Enable Android Wireless Debugging or connect and trust an iPhone.", id: :no_devices, wrap: true
        else
          state.devices.each do |device|
            safe_id = device.fetch(:id).gsub(/[^a-zA-Z0-9_.:-]/, "_")
            container id: "device.#{safe_id}", padding: 10, spacing: 6, bordered: true do
              row spacing: 8 do
                icon(device.fetch(:platform) == "iOS" ? "\uf179" : "\uf17b")
                column spacing: 2 do
                  text device.fetch(:name), style: :heading
                  text "#{device.fetch(:platform)} · #{device.fetch(:transport)} · #{device.fetch(:connected) ? 'Connected' : 'Available'}",
                       style: :caption
                end
              end
              row spacing: 7 do
                if device.fetch(:connected)
                  button(device.fetch(:platform) == "iOS" ? "Mirror" : "Open Phone", id: "open.#{safe_id}") do
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
                  button("Connect", id: "connect.#{safe_id}") do
                    async { notify_result.call(backend.connect(device.fetch(:id))); refresh.call }
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
              text device.fetch(:capabilities).map { |name, status| "#{name}: #{status}" }.join(" · "),
                   style: :caption, wrap: true
            end
          end
        end
      end

      section_header "Android options"
      audio_toggle = toggle("Forward audio", checked: state.audio, id: :audio) { |event| state.audio = event.fetch("value") }
      bind(audio_toggle, :checked) { state.audio }
      screen_toggle = toggle("Turn physical screen off", checked: state.screen_off, id: :screen_off) { |event| state.screen_off = event.fetch("value") }
      bind(screen_toggle, :checked) { state.screen_off }
      fullscreen_toggle = toggle("Start fullscreen", checked: state.fullscreen, id: :fullscreen) { |event| state.fullscreen = event.fetch("value") }
      bind(fullscreen_toggle, :checked) { state.fullscreen }
      size_field = number_field(state.max_size, id: :max_size, label: "Maximum resolution", from: 0, to: 7680, step: 160) { |event| state.max_size = event.fetch("value") }
      bind(size_field, :value) { state.max_size }
      fps_field = number_field(state.max_fps, id: :max_fps, label: "Maximum FPS", from: 1, to: 240, step: 5) { |event| state.max_fps = event.fetch("value") }
      bind(fps_field, :value) { state.max_fps }
      bitrate_field = number_field(state.bitrate_mbps, id: :bitrate, label: "Bitrate Mbps", from: 1, to: 100) { |event| state.bitrate_mbps = event.fetch("value") }
      bind(bitrate_field, :value) { state.bitrate_mbps }

      section_header "Pair Android"
      row spacing: 8 do
        text_field "", id: :pair_address, placeholder: "IP:pairing-port" do |event|
          state.pair_address = event.fetch("value")
        end
        text_field "", id: :pair_code, placeholder: "Pairing code" do |event|
          state.pair_code = event.fetch("value")
        end
        button "Pair", id: :pair do
          async do
            notify_result.call(backend.pair_android(state.pair_address, state.pair_code))
            refresh.call
          end
        end
      end

      row spacing: 8 do
        button "Start AirPlay", id: :airplay_start do
          async { notify_result.call(backend.start_airplay(fullscreen: state.fullscreen)) }
        end
        button "Stop AirPlay", id: :airplay_stop do
          async { notify_result.call(backend.stop_airplay) }
        end
      end
    end
    end
  end

  after(0.05, &refresh)
  every(5, &refresh)
end
