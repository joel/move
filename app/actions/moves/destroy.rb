# frozen_string_literal: true

module Moves
  # Permanently removes a Move and everything it owns (#432 — today only the
  # onboarding sample is removable from the UI). A hard delete, not a discard: the
  # user wants it gone.
  #
  # The app soft-deletes elsewhere (boxes/items via discard), so the *hard*-delete
  # cascade order was never exercised — and relying on `move.destroy!`'s
  # `dependent: :destroy` cascade breaks here three ways: (1) discarded descendants
  # are invisible to the `kept` default scope and would orphan / FK-block the delete;
  # (2) `Activity` is append-only (`readonly?`) so destroying its rows raises; and
  # (3) recognition items/suggestions/runs cross-reference `media` through FKs with no
  # `ON DELETE`, so the association order deletes a parent before its child.
  #
  # So we delete every descendant explicitly with `unscoped.delete_all` in child-first
  # FK order (which also reaches discarded rows and skips readonly callbacks), purging
  # Active Storage blobs by hand since `delete_all` fires no Active Storage callbacks.
  class Destroy < BaseAction
    # Move-owned tables in child-first order: no row is deleted while a still-present,
    # no-`ON DELETE` FK references it. (`item_search_documents` is omitted — its
    # item_id/move_id FKs are `ON DELETE CASCADE`, so the DB removes it for us.)
    DELETE_ORDER = [
      RecognitionSuggestion, RecognitionRun, Item, Media,
      Activity, IndexingRun, LabelPrintRun, MoveIntegrationToken, MoveMembership,
      Box, Room
    ].freeze

    # Models holding Active Storage attachments whose blobs we purge explicitly.
    ATTACHMENT_MODELS = [Media, LabelPrintRun].freeze

    def call(move:)
      move_id = move.id
      yield teardown(move)
      yield emit_event(move_id)
      Success(move_id)
    end

    private

    def teardown(move)
      # Capture attachment ids before any row is gone (delete_all skips the purge
      # callback, so blobs would otherwise orphan in storage).
      attachment_ids = attachment_ids_for(move)
      ActiveRecord::Base.transaction do
        DELETE_ORDER.each { |model| model.unscoped.where(move_id: move.id).delete_all }
        Move.unscoped.where(id: move.id).delete_all
      end
      purge_blobs(attachment_ids)
      Success()
    rescue ActiveRecord::InvalidForeignKey, ActiveRecord::StatementInvalid => e
      Failure(e.message)
    end

    def attachment_ids_for(move)
      ATTACHMENT_MODELS.flat_map do |model|
        record_ids = model.unscoped.where(move_id: move.id).pluck(:id)
        next [] if record_ids.empty?

        ActiveStorage::Attachment
          .where(record_type: model.name, record_id: record_ids).pluck(:id)
      end
    end

    # After the rows are gone, purge the (now-orphaned) attachments + their blobs.
    def purge_blobs(attachment_ids)
      ActiveStorage::Attachment.where(id: attachment_ids).find_each(&:purge_later)
    end

    def emit_event(move_id)
      Rails.event.notify("move.destroyed", move_id: move_id)
      Success()
    end
  end
end
