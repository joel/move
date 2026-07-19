# frozen_string_literal: true

# Wire the insurance-export audit to the `insurance.*` domain events (Rails 8.1
# Rails.event, #702). InsuranceDeclarations::Generate and
# InsuranceDossierRuns::Start emit on each export and the subscriber writes the
# audit line — a side effect driven by events, not a model callback (AGENTS.md
# §2). Filtered to `insurance.*` to keep dispatch cheap.
Rails.application.config.after_initialize do
  Rails.event.subscribe(Insurance::AuditSubscriber.new) { |event| event[:name].start_with?("insurance.") }
end
