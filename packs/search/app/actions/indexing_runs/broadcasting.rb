# frozen_string_literal: true

module IndexingRuns
  # Pushes the live embedding control (provider selector + progress) to every
  # subscriber of a Move's indexing stream (#239), so the progress bar advances
  # and the selector unlocks without a reload. Rendered server-side via
  # ApplicationController.render (no request) inside the caller's Apartment tenant;
  # the replace target only exists for admins, so viewers get a harmless no-op.
  module Broadcasting
    private

    # A broadcast must never break its emitter (AGENTS.md §1 #4): broadcast_control
    # runs synchronously inside the emitting action — in the *request* path
    # (SetEmbeddingProvider / SetProviderKey / RemoveProviderKey → IndexingRuns::Start)
    # and inside RefreshDocumentJob (RecordProgress). A render/render-backend failure
    # here must not 500 the settings page or fail the job, so it is isolated: the
    # worst case is a missed live update, and the next progress event (or a reload)
    # re-renders the control. Mirrors Captures::SessionBroadcastSubscriber#broadcast (#241).

    #: (untyped move) -> void
    def broadcast_control(move)
      Turbo::StreamsChannel.broadcast_replace_to(
        move, :ai_indexing,
        target: Views::Settings::EmbeddingControl::ID,
        html: ApplicationController.render(Views::Settings::EmbeddingControl.new(move: move), layout: false)
      )
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- §1#4 broadcast must not break emitter
      Rails.logger.warn("[indexing] embedding control broadcast failed: #{e.class}: #{e.message}")
    end
  end
end
