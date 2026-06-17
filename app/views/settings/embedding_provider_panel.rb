# frozen_string_literal: true

module Views
  module Settings
    # #232 / #242 — per-Move semantic-search (embedding) provider selector
    # (fake/openai/gemini/voyage). Keys are managed in the shared AI Capability
    # panel; this is a pure chooser. Thin wrapper: it mounts the Move's indexing
    # cable source (kept stable across switches) and renders the re-renderable
    # EmbeddingPanelBody. Its own card in the Settings AI region.
    class EmbeddingProviderPanel < Views::Base
      include Phlex::Rails::Helpers::TurboStreamFrom

      def initialize(move:, manage:)
        @move = move
        @manage = manage
      end

      def view_template
        div(class: "flex flex-col gap-4") do
          # Subscribe to this Move's indexing stream so re-embedding progress (and
          # the selector unlocking on completion) arrives live over ActionCable —
          # no polling (#239). Mounted in the wrapper so it survives a provider
          # switch that replaces only the body (#247). Binds to the unique Move.
          turbo_stream_from(@move, :ai_indexing)
          render Views::Settings::EmbeddingPanelBody.new(move: @move, manage: @manage)
        end
      end
    end
  end
end
