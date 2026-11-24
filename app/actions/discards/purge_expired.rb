# frozen_string_literal: true

module Discards
  # Hard-deletes soft-deleted records whose retention window has lapsed
  # (Discardable::RETENTION) — the other half of the discard/restore contract: a
  # deleted record is restorable for the window, then genuinely gone, blobs
  # included. Caller owns tenant context (PurgeExpiredDiscardsJob switches).
  #
  # Child-first model passes (Items → Media → Boxes): Discards::Cascade discards
  # children before their parent, so an expired parent's batch children are always
  # expired too — the earlier passes clear them, and no destroy is ever FK-blocked
  # by a surviving discarded child (the kept-scope trap documented on Box#items).
  # Per-record `destroy!` (not delete_all) fires the has_one_attached purge that
  # frees the blob plus the dependent: :destroy chains; a discarded box's
  # kept-but-unreachable children (media are not in its discard cascade) go down
  # with it — no surface can reach them and preserving them would orphan blobs.
  # Activity rows are append-only with no subject FK, so feed history survives;
  # the feed renders a purged subject with fallback copy and no Restore button.
  #
  # System-level maintenance, deliberately NOT guarded by ensure_writable: that
  # guard is for user-facing mutations (Moves::Destroy skips it too), and skipping
  # archived Moves would make retention unbounded for exactly the moves most
  # likely to hold stale discards.
  #
  # Accepted edges (rare, consistent with existing semantics — see #582):
  # - A photo bound only by a recovery manual-add (no suggestion rows) re-reads as
  #   orphaned once its purged item row is gone, so recovery may re-offer it.
  # - Recognition rows keep their historical box on Photos::Move (#317), so a
  #   moved-away live photo loses that history when its original box purges.
  # - A purged box's number returns to the Boxes::Create MAX(number) pool.
  class PurgeExpired < BaseAction
    # Child-first: items reference media (source_media_id) and boxes (box_id);
    # media reference boxes. Same rationale as Moves::Destroy::DELETE_ORDER.
    PASSES = [Item, Media, Box].freeze

    #: (?cutoff: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(cutoff: Discardable::RETENTION.ago)
      counts = PASSES.to_h { |model| [model.name.underscore.to_sym, purge_pass(model, cutoff)] }
      yield emit_event(counts)
      Success(counts)
    end

    private

    #: (untyped model, untyped cutoff) -> Integer
    def purge_pass(model, cutoff)
      purged = 0
      model.retention_expired(cutoff).find_each do |record|
        purged += 1 if purge_record(record, cutoff)
      end
      purged
    end

    # One transaction per record — the reference-detach and the destroy commit or
    # roll back together (never one giant sweep transaction). Per-record rescue:
    # one FK surprise skips that record (it retries a later night) instead of
    # aborting the whole sweep.

    #: (untyped record, untyped cutoff) -> bool
    def purge_record(record, cutoff)
      ActiveRecord::Base.transaction do
        root = lock_batch_root(record)
        record.lock!
        # Re-verify under lock: a Restore clicked between the batch fetch and this
        # transaction must win — never destroy a record that is kept again.
        return false unless record.discarded? && record.discarded_at <= cutoff
        return false unless batch_root_expired?(record, root, cutoff)

        detach_inbound_references(record)
        record.destroy!
      end
      true
    rescue ActiveRecord::RecordNotFound
      false # the row vanished under us — nothing left to purge
    rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::StatementInvalid => e
      Rails.event.notify("discards.purge_failed",
                         record_type: record.class.name, record_id: record.id, error: e.class.name)
      false
    end

    # A cascade child is purged under its batch root's row lock (#913) — the
    # lock Discards::CascadeRestore holds while it re-checks the root's
    # retention and restores the children. Without it the purge could delete a
    # child after that re-check passed and before restore_children read it, and
    # the root would come back without it. Parent before child, like every
    # cascade path. Roots are the child's direct parent: the cascade graph is
    # one level deep (Box → items, Media → items). Nil when the record has no
    # parent trace or the parent row is gone.

    #: (untyped record) -> untyped
    def lock_batch_root(record)
      klass = PASSES.find { |model| model.name == record.discarded_by_parent_type }
      return unless klass

      klass.with_discarded.lock(PARENT_ROW_LOCK).find_by(id: record.discarded_by_parent_id)
    end

    # A batch child is judged by its root's retention, not its own: Cascade
    # stamps children a moment before their root, so the cutoff can fall between
    # them — the child would be expired while the root is still restorable.
    # Purge it only once the root is past the cutoff too. The trace is re-read
    # under the record lock; if it no longer names the locked root (re-deleted
    # meanwhile), skip and let a later night decide.

    #: (untyped record, untyped root, untyped cutoff) -> bool
    def batch_root_expired?(record, root, cutoff)
      return true if record.discarded_by_parent_id.nil?
      return false if root && root.id != record.discarded_by_parent_id
      return true unless root&.discarded? && root.discard_batch_id == record.discard_batch_id

      root.discarded_at <= cutoff
    end

    # Nullifies the two inbound RESTRICT FKs no dependent option covers (Postgres
    # default NO ACTION would block the destroy):
    # - `recognition_suggestions.item_id` — nullified, NOT deleted: a surviving
    #   suggestion keeps Media#orphaned? false, so a purged item never re-offers
    #   recovery and a duplicate re-add (#198).
    # - `items.source_media_id` — an item moved to another box keeps a dangling
    #   source_media_id (#577); `with_discarded` because a discarded-but-unexpired
    #   item may reference it too. The survivor keeps its data, loses the photo,
    #   and becomes eligible for AI image generation again.
    # The Box pass covers both for everything the box still owns (its kept media
    # and any kept item are destroyed with it by the dependent chain, while their
    # referencing rows may live in other boxes).

    #: (untyped record) -> void
    def detach_inbound_references(record)
      case record
      when Item
        RecognitionSuggestion.where(item_id: record.id)
                             .update_all(item_id: nil) # rubocop:disable Rails/SkipsModelValidations
      when Media
        Item.with_discarded.where(source_media_id: record.id)
            .update_all(source_media_id: nil) # rubocop:disable Rails/SkipsModelValidations
      when Box
        Item.with_discarded
            .where(source_media_id: Media.with_discarded.where(box_id: record.id).select(:id))
            .update_all(source_media_id: nil) # rubocop:disable Rails/SkipsModelValidations
        RecognitionSuggestion
          .where(item_id: Item.with_discarded.where(box_id: record.id).select(:id))
          .update_all(item_id: nil) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    # Observability only — Activity::Builder ignores unknown event names, so no
    # feed row is created (the purge is invisible infra by design).

    #: (untyped counts) -> Dry::Monads::Success[nil]
    def emit_event(counts)
      Rails.event.notify("discards.purged", **counts) if counts.values.sum.positive?
      Success()
    end
  end
end
