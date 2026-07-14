# frozen_string_literal: true

# Wire item clusters (#625/#631) to the domain events (Rails 8.1 Rails.event).
# The subscriber claim-debounces a background recompute per Move on item
# lifecycle + embedding-space events, so clustering is an event-driven side
# effect of the actions — never a model callback (AGENTS.md §2). Filtered to
# the two prefixes to keep dispatch cheap.
Rails.application.config.after_initialize do
  Rails.event.subscribe(Clusters::RefreshSubscriber.new) do |event|
    event[:name].start_with?("item.", "box.", "move.")
  end
  # Live gallery Groups grid (#633): a finished recompute replaces the grid for
  # every connected viewer over the Move's :gallery_groups stream.
  Rails.event.subscribe(Clusters::BroadcastSubscriber.new) do |event|
    event[:name] == "clusters.recomputed"
  end
end
