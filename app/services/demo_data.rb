# frozen_string_literal: true

# Namespace + config for the onboarding sample-Move feature (#432).
module DemoData
  # Whether `organization.created` auto-provisions a sample Move. On by default;
  # db/seeds.rb turns it OFF while it builds the dev showcase Move explicitly, so
  # the demo tenant doesn't also get an auto-provisioned duplicate.
  mattr_accessor :auto_provision, default: true

  def self.auto_provision?
    auto_provision
  end
end
