# frozen_string_literal: true

module IndexingRuns
  # Pushes the live embedding control (provider selector + progress) to every
  # subscriber of a Move's indexing stream (#239), so the progress bar advances
  # and the selector unlocks without a reload. Rendered server-side via
  # ApplicationController.render (no request) inside the caller's Apartment tenant;
  # the replace target only exists for admins, so viewers get a harmless no-op.
  module Broadcasting
    private

    def broadcast_control(move)
      Turbo::StreamsChannel.broadcast_replace_to(
        move, :ai_indexing,
        target: Views::Settings::EmbeddingControl::ID,
        html: ApplicationController.render(Views::Settings::EmbeddingControl.new(move: move), layout: false)
      )
    end
  end
end
