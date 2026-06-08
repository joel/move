# frozen_string_literal: true

# Wire the D9 manifest audit to the `manifest.viewed` domain event (Rails 8.1
# Rails.event). Manifests::Generate emits on each authenticated manifest read and
# the subscriber writes the audit line — a side effect driven by events, not a
# model callback (AGENTS.md §2). Filtered to `manifest.*` to keep dispatch cheap.
Rails.application.config.after_initialize do
  Rails.event.subscribe(Manifests::AuditSubscriber.new) { |event| event[:name].start_with?("manifest.") }
end
