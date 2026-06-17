# frozen_string_literal: true

module ApplicationCable
  # Base channel. Turbo::StreamsChannel (turbo-rails) inherits from this, so it
  # must exist for Turbo Stream broadcasting to load.
  class Channel < ActionCable::Channel::Base
  end
end
