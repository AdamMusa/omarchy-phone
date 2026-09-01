# frozen_string_literal: true

# The embedded runtime resolves project files from the plugin root.
require_relative "lib/phone_backend"

state_dir = ENV.fetch("RUNNER_TEMP", "/tmp")
backend = PhoneBackend.allocate
backend.instance_variable_set(:@state_dir, state_dir)
pid = backend.send(:spawn_detached, ["/bin/true"], "omarchy-phone-runtime-api-check")

raise "Zui.spawn_detached did not return a child pid" unless pid.to_i.positive?

log_path = File.join(state_dir, "omarchy-phone-runtime-api-check.log")
File.delete(log_path) if File.file?(log_path)
