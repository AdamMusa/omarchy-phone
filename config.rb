# frozen_string_literal: true

OmarchyUI.configure do
  type :plugin
  id "izeesoft.omarchy-phone"
  name "Omarchy Phone"
  slug "omarchy-phone"
  version "0.2.3"
  author "Adam Moussa Ali"
  license "MIT"
  description "Ruby-powered Android control and iPhone AirPlay mirroring for Omarchy."
  entrypoint "main.rb"

  bar_widget do
    display_name "Omarchy Phone"
    description "Discover, connect, mirror, and control nearby phones."
    category "Network"
    default_section :right
  end
end
