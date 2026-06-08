# frozen_string_literal: true

# Wire the D8 search projection to item domain events (Rails 8.1 Rails.event).
# The subscriber enqueues a background reindex on item.created/updated/moved, so
# search indexing is an event-driven side effect of the actions — never a model
# callback (AGENTS.md §2). Filtered to `item.*` to keep dispatch cheap.
Rails.application.config.after_initialize do
  Rails.event.subscribe(Search::IndexSubscriber.new) { |event| event[:name].start_with?("item.") }
end
