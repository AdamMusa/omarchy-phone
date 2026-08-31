# frozen_string_literal: true

require "json"
require "digest"
require "thread"

require "minitest/autorun"
require "tmpdir"

module OmarchyUI
  class CommandTimeout < StandardError; end
  class CommandOutputLimit < StandardError; end
end

require_relative "../lib/phone_backend"

class PhoneBackendTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_bundled_runtime_matches_declared_digest
    checksum, filename = File.read(File.join(ROOT, "omarchy-ui-runtime.sha256")).split

    assert_equal "omarchy-ui-runtime", filename
    assert_equal checksum, Digest::SHA256.file(File.join(ROOT, filename)).hexdigest
  end

  def test_qml_bridge_is_compiled_and_checksummed
    report = JSON.parse(File.read(File.join(ROOT, "omarchy-ui-qml-bundle.json")))
    checksum = File.read(File.join(ROOT, "omarchy-ui-qml-bundle.sha256"))

    assert_equal "qt-aot-qml-module", report.fetch("format")
    assert_equal %w[BarWidget.qml Panel.qml Service.qml], report.fetch("entry_shims").sort
    report.fetch("artifacts").each do |artifact|
      path = File.join(ROOT, artifact.fetch("path"))
      assert_equal artifact.fetch("sha256"), Digest::SHA256.file(path).hexdigest
      assert_includes checksum, artifact.fetch("sha256")
    end
  end

  def test_discovery_lines_have_item_and_line_limits
    backend = PhoneBackend.allocate
    lines = backend.send(:bounded_lines, ("x" * 2048 + "\n") * 100)

    assert_equal 64, lines.length
    assert lines.all? { |line| line.length == 1024 }
  end

  def test_external_text_is_bounded_and_control_characters_are_removed
    backend = PhoneBackend.allocate

    assert_equal "phoneok", backend.send(:bounded_text, "phone\0ok", 20)
    assert_equal "abcd", backend.send(:bounded_text, "abcdefgh", 4)
  end

  def test_stale_pid_identity_is_cleared_without_signaling
    Dir.mktmpdir do |directory|
      state = File.join(directory, "uxplay.pid")
      File.write(state, "#{Process.pid}\n0\nuxplay\n")

      PhoneBackend.new(state_dir: directory)

      refute_path_exists state
    end
  end

  def test_symlinked_pid_state_is_rejected_and_unlinked
    Dir.mktmpdir do |directory|
      target = File.join(directory, "target")
      state = File.join(directory, "uxplay.pid")
      File.write(target, "#{Process.pid}\n0\nuxplay\n")
      File.symlink(target, state)

      PhoneBackend.new(state_dir: directory)

      refute File.symlink?(state)
      assert_path_exists target
    end
  end

  def test_owned_uxplay_identity_can_be_loaded_and_stopped
    Dir.mktmpdir do |directory|
      executable = File.join(directory, "uxplay")
      File.symlink("/bin/sleep", executable)
      pid = Process.spawn(executable, "30", pgroup: true)
      probe = PhoneBackend.allocate
      identity = nil
      20.times do
        identity = probe.send(:process_identity, pid)
        break if identity && identity["command"] == "uxplay"
        sleep(0.01)
      end
      File.write(File.join(directory, "uxplay.pid"), "#{pid}\n#{identity.fetch("start_time")}\nuxplay\n")

      backend = PhoneBackend.new(state_dir: directory)

      assert backend.airplay_running?
      assert backend.stop_airplay.ok
      Process.wait(pid)
      refute backend.airplay_running?
    ensure
      Process.kill("KILL", -pid) if pid && process_group_alive?(pid)
      Process.wait(pid) if pid
    end
  rescue Errno::ECHILD
    nil
  end

  private

  def process_group_alive?(pid)
    Process.kill(0, -pid)
    true
  rescue Errno::ESRCH
    false
  end
end
