# frozen_string_literal: true

# Wire the Activity Feed to the domain event stream (Rails 8.1 Rails.event).
# Activity::RecordSubscriber writes one append-only row per recorded event; the
# filter keeps dispatch cheap by only waking the subscriber for events the
# Builder actually maps (AGENTS.md §2, like manifest_audit / search_indexing).
Rails.application.config.after_initialize do
  Rails.event.subscribe(Activity::RecordSubscriber.new) do |event|
    Activity::Builder.records?(event[:name])
  end
end
