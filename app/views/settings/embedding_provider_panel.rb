# frozen_string_literal: true

module Views
  module Settings
    # #232 / #242 — per-Move semantic-search (embedding) provider selector
    # (fake/openai/gemini/voyage). Keys are managed in the shared AI Capability
    # panel; this is a pure chooser. Admins get the interactive selector (with the
    # live #239 indexing status); everyone else sees the active provider read-only.
    # Its own card in the Settings AI region.
    class EmbeddingProviderPanel < Views::Base
      include Phlex::Rails::Helpers::Routes
      include Phlex::Rails::Helpers::TurboStreamFrom

      def initialize(move:, manage:)
        @move = move
        @manage = manage
      end

      def view_template
        div(class: "flex flex-col gap-4") do
          # Subscribe to this Move's indexing stream so re-embedding progress (and
          # the selector unlocking on completion) arrives live over ActionCable —
          # no polling (#239). The signed name binds to the tenant-unique Move.
          turbo_stream_from(@move, :ai_indexing)
          div(class: "flex items-start justify-between gap-4") do
            div(class: "flex flex-col gap-1") do
              span(class: "text-headline-md text-text-warm") { t("title") }
              span(class: "text-body-md text-on-surface-variant") { t("subtitle") }
            end
            status_chip
          end
          @manage ? render(Views::Settings::EmbeddingControl.new(move: @move)) : readonly
        end
      end

      private

      def status_chip
        if @move.embedding_provider_ready?
          chip(t("status_active"), "bg-accent-sage/20 text-accent-sage")
        elsif Move::REAL_EMBEDDING_PROVIDERS.include?(@move.embedding_provider)
          chip(t("status_key_required"), "bg-secondary/20 text-secondary")
        else
          chip(t("status_off"), "bg-surface-container-high text-on-surface-variant")
        end
      end

      def chip(text, color)
        span(class: "#{color} rounded-full px-3 py-1 text-label-caps uppercase") { text }
      end

      def readonly
        span(class: "self-start rounded-full bg-surface-container-high px-4 py-2 text-body-md text-text-warm") do
          t("options.#{@move.embedding_provider}")
        end
      end

      def t(key)
        I18n.t("settings.show.recognition.embeddings.#{key}")
      end
    end
  end
end
