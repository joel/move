# frozen_string_literal: true

module ApplicationCable
  # The app's first ActionCable connection (#239). Progress is pushed over
  # turbo-rails Turbo Streams, which use **signed** stream names — a subscriber
  # can only join a stream whose signed name was rendered into a page it was
  # already authorized to see (turbo_stream_from). So this connection needs no
  # per-user identification: the signed-name check is the authorization boundary,
  # and stream names are derived from the tenant-unique Move (uuid), so one org
  # never receives another's broadcasts.
  class Connection < ActionCable::Connection::Base
  end
end
