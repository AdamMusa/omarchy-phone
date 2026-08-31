# source: main.rb
# frozen_string_literal: true


# source: lib/phone_backend.rb
# frozen_string_literal: true

class PhoneBackend
  Result = Struct.new(:ok, :message, keyword_init: true)
  COMMAND_OUTPUT_LIMIT = 65_536
  MAX_DISCOVERY_ITEMS = 64
  MAX_EXTERNAL_STRING = 256

  def initialize(state_dir: File.expand_path("~/.local/state/omarchy-phone-ruby"))
    @state_dir = state_dir
    @action_lock = Mutex.new
    @airplay_pid_path = File.join(@state_dir, "uxplay.pid")
    @android_address_path = File.join(@state_dir, "android-address")
    @android_pair_path = File.join(@state_dir, "android-paired-ip")
    @airplay_pid = nil
    create_directory(@state_dir)
    @airplay_pid = load_airplay_pid
    at_exit { stop_airplay } if Kernel.respond_to?(:at_exit)
  end

  def snapshot
    devices = android_devices + ios_devices + airplay_devices
    {
      devices: devices.sort_by { |device| [device.fetch(:connected) ? 0 : 1, device.fetch(:name).downcase] },
      backends: backend_status,
      captured_at: Time.now.to_i
    }
  end

  def refresh = snapshot

  def open(device, options = {})
    return start_airplay(fullscreen: options[:fullscreen] || options["fullscreen"]) if device["platform"] == "iOS"
    argv = ["scrcpy", "--serial", device.fetch("id").to_s, "--keyboard=uhid"]
    argv << "--fullscreen" if truthy?(options, :fullscreen)
    argv << "--turn-screen-off" if truthy?(options, :screen_off)
    argv << "--no-audio" unless options.fetch(:audio, options.fetch("audio", true))
    add_numeric_option(argv, "--max-size", options, :max_size)
    add_numeric_option(argv, "--max-fps", options, :max_fps)
    bitrate = option(options, :bitrate_mbps)
    argv << "--video-bit-rate=#{bitrate}M" if bitrate.to_i.positive?
    spawn_gui(argv, "scrcpy")
  end

  def connect(device_id)
    address = device_id.to_s.strip
    address = discover_android_connection(address) if android_ip?(address)
    return Result.new(ok: false, message: "Connection port is not available yet. Keep Wireless debugging enabled and retry.") unless address
    return Result.new(ok: false, message: "Enter the IP and connection port shown on Wireless debugging") unless android_endpoint?(address)
    command(["adb", "disconnect", address], timeout: 5)
    result = action(["adb", "connect", address], "Connected to #{address}")
    failed = result.message.downcase.include?("failed to connect") || result.message.downcase.include?("unable to connect")
    result = Result.new(ok: false, message: result.message) if result.ok && failed
    if result.ok
      ready = false
      10.times do
        state = command(["adb", "-s", address, "get-state"], timeout: 3)
        if state&.success? && state.stdout.strip == "device"
          ready = true
          break
        end
        sleep(0.3)
      end
      result = Result.new(ok: false, message: "Android connected but its ADB transport is still offline. Wake the phone and retry.") unless ready
    end
    remember_android_address(address) if result.ok
    result
  end
  def last_android_address
    File.file?(@android_address_path) ? File.read(@android_address_path).strip : ""
  end
  def disconnect(device_id) = action(["adb", "disconnect", device_id.to_s], "Disconnected #{device_id}")
  def forget(device_id)
    result = disconnect(device_id)
    File.delete(@android_pair_path) if File.file?(@android_pair_path)
    result
  end
  def pair_android(address, code)
    address = address.to_s.strip
    code = code.to_s.strip
    return Result.new(ok: false, message: "Enter the IP and pairing port from the pairing-code popup") unless android_endpoint?(address)
    return Result.new(ok: false, message: "Enter the current six-digit pairing code") unless code.length == 6 && decimal_string?(code)

    result = action(["adb", "pair", address, code], "Paired #{address}")
    if !result.ok && result.message.include?("protocol fault")
      Result.new(ok: false, message: "Pairing failed. Open a new pairing-code popup and retry before the code expires.")
    elsif result.ok
      remember_android_pair(address.split(":", 2).first)
      Result.new(ok: true, message: "Pairing complete. Select the paired phone, then Connect when its service is available.")
    else
      result
    end
  end
  def trust_iphone(device_id) = action(["idevicepair", "-u", device_id.to_s, "pair"], "Trusted iPhone")

  def start_airplay(fullscreen: false)
    @action_lock.synchronize do
      return Result.new(ok: true, message: "AirPlay receiver is already running") if owned_airplay_process?(@airplay_pid)
      pin = format("%04d", rand(10_000))
      argv = ["uxplay", "-n", "Omarchy", "-nh", "-pin", pin, "-p", "7100"]
      argv << "-fs" if fullscreen
      @airplay_pid = spawn_detached(argv, "uxplay")
      write_airplay_identity(@airplay_pid)
      Result.new(ok: true, message: "AirPlay receiver started — PIN #{pin}")
    rescue Errno::ENOENT
      Result.new(ok: false, message: "UxPlay is not installed")
    end
  end

  def stop_airplay
    @action_lock.synchronize do
      unless owned_airplay_process?(@airplay_pid)
        clear_airplay_pid
        return Result.new(ok: true, message: "AirPlay receiver is stopped")
      end
      Process.kill("TERM", -@airplay_pid)
      clear_airplay_pid
      Result.new(ok: true, message: "AirPlay receiver stopped")
    rescue Errno::ESRCH
      clear_airplay_pid
      Result.new(ok: true, message: "AirPlay receiver stopped")
    end
  end

  def airplay_running? = owned_airplay_process?(@airplay_pid)

  private

  def create_directory(path)
    current = path.start_with?(File::SEPARATOR) ? File::SEPARATOR : ""
    path.split(File::SEPARATOR).each do |part|
      next if part.empty?

      current = File.join(current, part)
      Dir.mkdir(current) unless File.directory?(current)
    end
  end

  def android_endpoint?(value)
    address = value.split(":")
    return false unless address.length == 2
    octets = address[0].split(".")
    return false unless octets.length == 4 && octets.all? { |octet| decimal_string?(octet) && octet.to_i <= 255 }
    decimal_string?(address[1]) && address[1].to_i.between?(1, 65_535)
  end

  def android_ip?(value)
    octets = value.split(".")
    octets.length == 4 && octets.all? { |octet| decimal_string?(octet) && octet.to_i <= 255 }
  end

  def discover_android_connection(phone_ip)
    result = command(["avahi-browse", "-rtp", "_adb-tls-connect._tcp"], timeout: 8)
    return nil unless result&.success?
    bounded_lines(result.stdout).each do |line|
      fields = line.strip.split(";")
      next unless fields[0] == "=" && fields[4] == "_adb-tls-connect._tcp"
      return "#{fields[7]}:#{fields[8]}" if fields[7] == phone_ip && fields[8].to_i.positive?
    end
    nil
  end

  def decimal_string?(value)
    !value.empty? && value.each_byte.all? { |byte| byte >= 48 && byte <= 57 }
  end

  def load_airplay_pid
    unless safe_regular_file?(@airplay_pid_path)
      clear_airplay_pid if File.exist?(@airplay_pid_path) || symlink_path?(@airplay_pid_path)
      return nil
    end
    fields = File.read(@airplay_pid_path, 256).split("\n")
    pid = Integer(fields[0])
    saved_identity = { "start_time" => fields[1].to_s, "command" => fields[2].to_s }
    return pid if valid_airplay_identity?(pid, saved_identity)
    clear_airplay_pid
    nil
  rescue ArgumentError, SystemCallError
    clear_airplay_pid
    nil
  end

  def clear_airplay_pid
    @airplay_pid = nil
    File.delete(@airplay_pid_path) if File.exist?(@airplay_pid_path) || symlink_path?(@airplay_pid_path)
  end

  def backend_status
    {
      android: { adb: available?("adb"), scrcpy: available?("scrcpy") },
      ios: { libimobiledevice: available?("idevice_id"), airplay: available?("uxplay") }
    }
  end

  def android_devices
    result = command(["adb", "devices", "-l"], timeout: 5)
    return [] unless result&.success?
    attached = bounded_lines(result.stdout).drop(1).filter_map do |line|
      serial, status, *details = line.strip.split
      next if serial.nil? || status.nil?
      fields = details.filter_map { |field| field.split(":", 2) if field.include?(":") }.to_h
      device = {
        id: bounded_text(serial), name: bounded_text(fields["model"]&.tr("_", " ") || serial),
        platform: "Android", connected: status == "device", paired: true,
        transport: serial.include?(":") ? "Wi-Fi" : "USB",
        model: fields["model"], capabilities: android_capabilities(status == "device")
      }
      remember_android_address(serial) if device.fetch(:connected) && serial.include?(":")
      device
    end
    merge_paired_android(merge_mdns_devices(attached))
  end

  def ios_devices
    result = command(["idevice_id", "-l"], timeout: 5)
    return [] unless result&.success?
    bounded_lines(result.stdout).filter_map do |line|
      id = line.strip
      next if id.empty?
      name = command(["ideviceinfo", "-u", id, "-k", "DeviceName"], timeout: 3)&.stdout&.strip
      model = command(["ideviceinfo", "-u", id, "-k", "ProductType"], timeout: 3)&.stdout&.strip
      {
        id: bounded_text(id), name: bounded_text(name.to_s.empty? ? "iPhone" : name), platform: "iOS",
        connected: true, paired: true, transport: "USB", model: bounded_text(model),
        capabilities: { mirror: "available", trust: "available", files: "experimental" }
      }
    end
  end

  def airplay_devices
    return [] unless owned_airplay_process?(@airplay_pid)
    result = command(["ss", "-Hnt", "state", "established", "sport", "=", ":7100"], timeout: 3)
    return [] unless result&.success?
    bounded_lines(result.stdout).filter_map do |line|
      endpoint = line.strip.split.fetch(3, "")
      separator = endpoint.rindex(":")
      address = separator ? endpoint[0...separator] : endpoint
      address = address[1...-1] if address.start_with?("[") && address.end_with?("]")
      next if address.empty?
      {
        id: "airplay:#{address}", name: "AirPlay iPhone", platform: "iOS",
        connected: true, paired: true, transport: "AirPlay", model: nil,
        capabilities: { mirror: "active", audio: "active", control: "unavailable", files: "unavailable" }
      }
    end.uniq { |device| device.fetch(:id) }
  end

  def merge_mdns_devices(attached)
    result = command(["adb", "mdns", "services"], timeout: 5)
    return attached unless result&.success?
    known = attached.to_h { |device| [device.fetch(:id), device] }
    bounded_lines(result.stdout).each do |line|
      match = line.strip.match(/\A(.+?)\s+(_adb-tls-(?:connect|pairing)\._tcp\.?)\s+(\S+):(\d+)\z/)
      next unless match
      address = "#{match[3]}:#{match[4]}"
      next if known.key?(address) || match[2].include?("pairing")
      known[address] = {
        id: address, name: bounded_text(match[1].gsub("\\032", " ")), platform: "Android",
        connected: false, paired: true, transport: "Wi-Fi", model: nil,
        capabilities: android_capabilities(false)
      }
    end
    known.values
  end

  def merge_paired_android(devices)
    return devices unless File.file?(@android_pair_path)
    phone_ip = File.read(@android_pair_path).strip
    return devices if phone_ip.empty? || devices.any? { |device| device.fetch(:id).start_with?("#{phone_ip}:") }
    devices + [{
      id: phone_ip, name: "Paired Android", platform: "Android", connected: false,
      paired: true, transport: "Wi-Fi", model: nil, capabilities: android_capabilities(false)
    }]
  end

  def android_capabilities(connected)
    state = connected ? "available" : "unavailable"
    { mirror: state, control: state, audio: state, files: state }
  end

  def action(argv, success_message)
    @action_lock.synchronize do
      result = command(argv, timeout: 20)
      return Result.new(ok: false, message: "#{argv.first} is not installed") unless result
      return Result.new(ok: false, message: "#{argv.first} is not installed") if result.exitstatus == 127
      message = bounded_text([result.stdout, result.stderr].join(" ").strip, 512)
      failure = message.empty? ? "#{argv.first} failed with exit status #{result.exitstatus}" : message
      Result.new(ok: result.success?, message: result.success? ? (message.empty? ? success_message : message) : failure)
    end
  end

  def spawn_gui(argv, name)
    spawn_detached(argv, name)
    Result.new(ok: true, message: "Opened phone")
  rescue Errno::ENOENT
    Result.new(ok: false, message: "#{argv.first} is not installed")
  end

  def command(argv, timeout:)
    OmarchyUI::Command.run(argv, timeout:, max_output_bytes: COMMAND_OUTPUT_LIMIT)
  rescue Errno::ENOENT, OmarchyUI::CommandTimeout, OmarchyUI::CommandOutputLimit
    nil
  end

  def spawn_detached(argv, name)
    OmarchyUI.spawn_detached(argv, File.join(@state_dir, "#{name}.log"))
  end

  def available?(program)
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |path|
      candidate = File.join(path, program)
      File.respond_to?(:executable?) ? File.executable?(candidate) : File.file?(candidate)
    end
  end

  def remember_android_address(address)
    File.open(@android_address_path, "w") { |file| file.write("#{address}\n") }
  end

  def remember_android_pair(phone_ip)
    File.open(@android_pair_path, "w") { |file| file.write("#{phone_ip}\n") }
  end

  def write_airplay_identity(pid)
    identity = nil
    20.times do
      identity = process_identity(pid)
      break if identity && identity["command"] == "uxplay"
      sleep(0.01)
    end
    raise "could not verify spawned UxPlay process" unless valid_airplay_identity?(pid, identity)
    raise "unsafe AirPlay state path" if File.exist?(@airplay_pid_path) && !safe_regular_file?(@airplay_pid_path)
    temporary = "#{@airplay_pid_path}.tmp-#{Process.pid}-#{rand(1_000_000)}"
    File.open(temporary, "w", 0o600) do |file|
      file.write("#{pid}\n#{identity.fetch("start_time")}\nuxplay\n")
    end
    File.rename(temporary, @airplay_pid_path)
  ensure
    File.delete(temporary) if temporary && File.file?(temporary)
  end

  def owned_airplay_process?(pid)
    return false unless pid
    valid_airplay_identity?(pid, process_identity(pid))
  end

  def valid_airplay_identity?(pid, saved_identity)
    current = process_identity(pid)
    current && saved_identity && pid.to_i.positive? &&
      current.fetch("process_group").to_i == pid.to_i &&
      current.fetch("start_time").to_s == saved_identity.fetch("start_time", "").to_s &&
      current.fetch("command") == "uxplay" && saved_identity.fetch("command", "") == "uxplay"
  end

  def process_identity(pid)
    return nil unless pid.to_i.positive?
    stat = File.read("/proc/#{pid}/stat", 4096)
    return nil unless stat
    closing_parenthesis = stat.rindex(")")
    return nil unless closing_parenthesis
    tail_text = stat[(closing_parenthesis + 2)..]
    return nil unless tail_text
    tail = tail_text.split
    command_data = File.read("/proc/#{pid}/cmdline", 4096)
    return nil unless command_data
    command_line = command_data.split("\0").first.to_s
    return nil if command_line.empty?
    {
      "process_group" => tail.fetch(2).to_i,
      "start_time" => tail.fetch(19),
      "command" => File.basename(command_line)
    }
  rescue SystemCallError, IndexError
    nil
  end

  def safe_regular_file?(path)
    File.file?(path) && !symlink_path?(path)
  end

  def symlink_path?(path)
    File.respond_to?(:symlink?) && File.symlink?(path)
  end

  def bounded_lines(output)
    output.to_s.each_line.first(MAX_DISCOVERY_ITEMS).map { |line| line[0, 1024] }
  end

  def bounded_text(value, limit = MAX_EXTERNAL_STRING)
    value.to_s.each_char.reject { |character| character.ord < 32 && character != "\n" && character != "\t" }.join[0, limit]
  end

  def truthy?(options, key) = options[key] == true || options[key.to_s] == true
  def option(options, key) = options.fetch(key, options[key.to_s])

  def add_numeric_option(argv, flag, options, key)
    value = option(options, key)
    argv << "#{flag}=#{value}" if value.to_i.positive?
  end
end


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
