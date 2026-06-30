# frozen_string_literal: true

module DemoData
  # Pushes the finished (or failed) sample-provisioning result to the Moves index of
  # everyone watching this org's demo stream (#432), so the "preparing…" placeholder
  # becomes the real Move list (or a fallback card) without a reload. The stream is
  # anchored on the Organization (a public/excluded record that exists before the
  # Move does and is unique per tenant — the signed stream name is the auth boundary).
  # Rendered server-side via ApplicationController.render inside the caller's tenant.
  module Reveal
    module_function

    # The org's demo_data_status MUST already be persisted to its terminal value
    # before this runs, so a page that loads after the broadcast reads the correct
    # state from the DB and never shows a stuck placeholder (the broadcast may land
    # in the void if no one is subscribed yet).
    def broadcast(organization)
      moves = Move.order(created_at: :desc).to_a
      Turbo::StreamsChannel.broadcast_replace_to(
        organization, :demo_provisioning,
        target: Components::Moves::Collection::ID,
        html: ApplicationController.render(
          Components::Moves::Collection.new(moves: moves, organization: organization),
          layout: false
        )
      )
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- §1#4 broadcast must not break the job
      Rails.logger.warn("[demo_data] reveal broadcast failed: #{e.class}: #{e.message}")
    end
  end
end
