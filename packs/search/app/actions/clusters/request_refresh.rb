# frozen_string_literal: true

# pack_public: true -- public API of packs/search: request a debounced cluster
# recompute (the RefreshSubscriber calls it on item events; PR 4's gallery
# lazily calls it for a Move that has never been clustered). See
# packwerk-boundaries.md for the sigil convention.

module Clusters
  # Claim-debounces cluster recomputes per Move (#631): a burst of item events
  # (one photo recognizing 15 items) collapses into ONE recompute. The claim is
  # a single atomic guarded UPDATE on the cluster_states singleton — only the
  # caller that flips refresh_pending false→true enqueues the delayed job
  # (mirroring the IndexingRuns::RecordProgress claim idiom); everyone else in
  # the window no-ops. The job releases the claim BEFORE computing, so events
  # landing mid-compute open a fresh window (trailing edge) and nothing is lost.
  class RequestRefresh < BaseAction
    # Long enough to absorb a recognition burst, short enough that the gallery
    # feels live. The prompt-side latency budget is the debounce + the compute.
    DEBOUNCE = 20.seconds

    # A held claim older than this is treated as abandoned — a process that
    # died between claiming and durably enqueuing (deploy SIGTERM, OOM) would
    # otherwise strand refresh_pending=true forever and freeze the Move's
    # clusters. Comfortably > DEBOUNCE + a slow compute; a late-but-alive job
    # that gets reclaimed past the TTL merely produces a duplicate run, which
    # Recompute's per-Move advisory lock serializes harmlessly. (The same
    # crash-recovery shape as Item::IMAGE_CLAIM_TTL.)
    STALE_AFTER = 5.minutes

    #: (move_id: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(move_id:)
      return Success(:already_pending) unless claim(move_id)

      enqueue(move_id)
    rescue ActiveRecord::InvalidForeignKey
      # The Move vanished between the event and this write — nothing to refresh.
      Failure(:move_deleted)
    end

    private

    # This runs synchronously inside the emitting action (via the subscriber),
    # so an enqueue failure must degrade, never raise — and it must RELEASE the
    # claim it just took, or the window stays pending forever with no job
    # coming. NotImplementedError is rescued explicitly (it is a ScriptError,
    # not a StandardError): the :inline test adapter raises it for scheduled
    # jobs, which is exactly this failure mode.

    #: (untyped move_id) -> Dry::Monads::Result[untyped, untyped]
    def enqueue(move_id)
      Clusters::RefreshJob.set(wait: DEBOUNCE).perform_later(move_id, tenant: Apartment::Tenant.current)
      Success(:enqueued)
    rescue NotImplementedError, StandardError => e # rubocop:disable Move/BroadRescue -- release the claim + degrade; a queue outage must not break the emitting action
      release(move_id)
      Rails.logger.warn("[clusters] refresh enqueue failed for move=#{move_id}: #{e.class}: #{e.message}")
      Failure(:enqueue_failed)
    end

    #: (untyped move_id) -> void
    def release(move_id)
      # rubocop:disable Rails/SkipsModelValidations -- undo of the atomic claim.
      ClusterState.where(move_id: move_id).update_all(refresh_pending: false)
      # rubocop:enable Rails/SkipsModelValidations
    end

    # The whole debounce protocol in ONE atomic statement: creates the state
    # singleton on first contact (id/flags default), takes the claim when the
    # window is open, AND recovers a stale claim past the TTL — the conflict
    # UPDATE's WHERE makes losing callers affect 0 rows. One round-trip on the
    # hot emitting path instead of insert-then-update; values are all binds.
    # Returns the claim timestamp on a win, nil when already pending (the
    # Item#claim_image_generation! shape).

    #: (untyped move_id) -> untyped
    def claim(move_id)
      now = Time.current
      sql = ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, { move_id: move_id, now: now, stale: STALE_AFTER.ago }])
        INSERT INTO cluster_states (move_id, refresh_pending, requested_at, created_at, updated_at)
        VALUES (:move_id, TRUE, :now, :now, :now)
        ON CONFLICT (move_id) DO UPDATE
          SET refresh_pending = TRUE, requested_at = :now, updated_at = :now
          WHERE cluster_states.refresh_pending = FALSE OR cluster_states.requested_at < :stale
      SQL
      ActiveRecord::Base.connection.exec_update(sql) == 1 ? now : nil
    end
  end
end
