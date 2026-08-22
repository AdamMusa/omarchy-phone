# frozen_string_literal: true

require "fileutils" unless Object.const_defined?(:MRUBY_VERSION)
require "json" unless Object.const_defined?(:JSON)
require "thread" unless Object.const_defined?(:Mutex)

class PhoneBackend
  Result = Struct.new(:ok, :message, keyword_init: true)

  def initialize(state_dir: File.expand_path("~/.local/state/omarchy-phone-ruby"))
    @state_dir = state_dir
    @action_lock = Mutex.new
    @airplay_pid_path = File.join(@state_dir, "uxplay.pid")
    @airplay_pid = nil
    if Object.const_defined?(:FileUtils)
      FileUtils.mkdir_p(@state_dir)
    else
      parts = @state_dir.split("/")
      current = @state_dir.start_with?("/") ? "/" : ""
      parts.each do |part|
        next if part.empty?
        current = File.join(current, part)
        Dir.mkdir(current) unless File.directory?(current)
      end
    end
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

  def connect(device_id) = action(["adb", "connect", device_id.to_s], "Connected to #{device_id}")
  def disconnect(device_id) = action(["adb", "disconnect", device_id.to_s], "Disconnected #{device_id}")
  def forget(device_id) = disconnect(device_id)
  def pair_android(address, code) = action(["adb", "pair", address.to_s, code.to_s], "Paired #{address}")
  def trust_iphone(device_id) = action(["idevicepair", "-u", device_id.to_s, "pair"], "Trusted iPhone")

  def start_airplay(fullscreen: false)
    @action_lock.synchronize do
      return Result.new(ok: true, message: "AirPlay receiver is already running") if process_alive?(@airplay_pid)
      pin = format("%04d", rand(10_000))
      argv = ["uxplay", "-n", "Omarchy", "-nh", "-pin", pin, "-p", "7100"]
      argv << "-fs" if fullscreen
      @airplay_pid = spawn_detached(argv, "uxplay")
      File.open(@airplay_pid_path, "w") { |file| file.write("#{@airplay_pid}\n") }
      Result.new(ok: true, message: "AirPlay receiver started — PIN #{pin}")
    rescue Errno::ENOENT
      Result.new(ok: false, message: "UxPlay is not installed")
    end
  end

  def stop_airplay
    @action_lock.synchronize do
      unless process_alive?(@airplay_pid)
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

  def airplay_running? = process_alive?(@airplay_pid)

  private

  def load_airplay_pid
    return nil unless File.file?(@airplay_pid_path)
    Integer(File.read(@airplay_pid_path).strip)
  rescue ArgumentError
    nil
  end

  def clear_airplay_pid
    @airplay_pid = nil
    File.delete(@airplay_pid_path) if File.file?(@airplay_pid_path)
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
    attached = result.stdout.lines.drop(1).filter_map do |line|
      serial, status, *details = line.strip.split
      next if serial.nil? || status.nil?
      fields = details.filter_map { |field| field.split(":", 2) if field.include?(":") }.to_h
      {
        id: serial, name: fields["model"]&.tr("_", " ") || serial,
        platform: "Android", connected: status == "device", paired: true,
        transport: serial.include?(":") ? "Wi-Fi" : "USB",
        model: fields["model"], capabilities: android_capabilities(status == "device")
      }
    end
    merge_mdns_devices(attached)
  end

  def ios_devices
    result = command(["idevice_id", "-l"], timeout: 5)
    return [] unless result&.success?
    result.stdout.lines.filter_map do |line|
      id = line.strip
      next if id.empty?
      name = command(["ideviceinfo", "-u", id, "-k", "DeviceName"], timeout: 3)&.stdout&.strip
      model = command(["ideviceinfo", "-u", id, "-k", "ProductType"], timeout: 3)&.stdout&.strip
      {
        id:, name: name.to_s.empty? ? "iPhone" : name, platform: "iOS",
        connected: true, paired: true, transport: "USB", model:,
        capabilities: { mirror: "available", trust: "available", files: "experimental" }
      }
    end
  end

  def airplay_devices
    return [] unless process_alive?(@airplay_pid)
    result = command(["ss", "-Hnt", "state", "established", "sport", "=", ":7100"], timeout: 3)
    return [] unless result&.success?
    result.stdout.lines.filter_map do |line|
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
    result.stdout.each_line do |line|
      match = line.strip.match(/\A(.+?)\s+(_adb-tls-(?:connect|pairing)\._tcp\.?)\s+(\S+):(\d+)\z/)
      next unless match
      address = "#{match[3]}:#{match[4]}"
      next if known.key?(address) || match[2].include?("pairing")
      known[address] = {
        id: address, name: match[1].gsub("\\032", " "), platform: "Android",
        connected: false, paired: true, transport: "Wi-Fi", model: nil,
        capabilities: android_capabilities(false)
      }
    end
    known.values
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
      message = [result.stdout, result.stderr].join(" ").strip
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
    OmarchyUI::Command.run(argv, timeout:)
  rescue Errno::ENOENT, OmarchyUI::CommandTimeout
    nil
  end

  def spawn_detached(argv, name)
    if Object.const_defined?(:MRUBY_VERSION)
      OmarchyUI.spawn_detached(argv, File.join(@state_dir, "#{name}.log"))
    else
      log = File.open(File.join(@state_dir, "#{name}.log"), "a")
      pid = Process.spawn(*argv, out: log, err: log, pgroup: true)
      log.close
      Process.detach(pid)
      pid
    end
  end

  def available?(program)
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |path|
      candidate = File.join(path, program)
      File.respond_to?(:executable?) ? File.executable?(candidate) : File.file?(candidate)
    end
  end

  def process_alive?(pid)
    return false unless pid
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  def truthy?(options, key) = options[key] == true || options[key.to_s] == true
  def option(options, key) = options.fetch(key, options[key.to_s])

  def add_numeric_option(argv, flag, options, key)
    value = option(options, key)
    argv << "#{flag}=#{value}" if value.to_i.positive?
  end
end
