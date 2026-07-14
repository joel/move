# frozen_string_literal: true

module Clusters
  # Runs the debounced cluster recompute for one Move (#631). Restores the
  # Apartment tenant (jobs never inherit request Current/tenant), releases the
  # debounce claim BEFORE computing — an event landing mid-compute must be able
  # to claim a fresh window (trailing edge), or its change would be silently
  # missing from the just-computed clusters with nothing re-enqueued — then
  # recomputes. Safe if the Move was since deleted (Recompute also degrades to
  # Failure(:move_deleted) if it vanishes mid-run).
  class RefreshJob < ApplicationJob
    queue_as :default

    # The claim is released before computing, so a transiently-failed compute
    # (connection reset mid-embed) would otherwise be recovered only by the
    # NEXT item event — indefinite staleness for a Move that just went quiet.
    # A bounded retry closes that: recomputes are idempotent and the per-Move
    # advisory lock serializes overlap. After the attempts are spent, the TTL'd
    # claim + the next event remain the backstop.
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform(move_id, tenant:)
      Apartment::Tenant.switch(tenant) do
        Current.tenant = tenant
        release_claim(move_id)
        move = Move.find_by(id: move_id)
        Clusters::Recompute.new.call(move: move) if move
      end
    end

    private

    def release_claim(move_id)
      # rubocop:disable Rails/SkipsModelValidations -- flag flip only; the claim
      # protocol (RequestRefresh) owns this column.
      ClusterState.where(move_id: move_id).update_all(refresh_pending: false)
      # rubocop:enable Rails/SkipsModelValidations
    end
  end
end
