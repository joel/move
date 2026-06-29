# frozen_string_literal: true

# Push the box-contents card live as item-image generation resolves (#416), an
# event-driven side effect (AGENTS §1#4 — never JS polling). Filtered to the two
# image events to keep dispatch cheap; the subscriber re-renders just that item's
# ItemCard and broadcasts it over Turbo Streams.
Rails.application.config.after_initialize do
  Rails.event.subscribe(Items::ImageBroadcastSubscriber.new) do |event|
    Items::ImageBroadcastSubscriber::EVENTS.include?(event[:name])
  end
end
