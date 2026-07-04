# frozen_string_literal: true

module Views
  module Settings
    # The re-renderable body of the Semantic Search panel — header + status chip +
    # selector (admin) / read-only label. Split out of EmbeddingProviderPanel so a
    # provider switch can replace it in place via Turbo Stream (#247) instead of a
    # full-page reload; the `turbo_stream_from` cable source stays mounted in the
    # parent, so the live (#239) subscription survives the swap. The stable id is
    # both the page anchor and the Turbo Stream replace target.
    class EmbeddingPanelBody < Views::Base
      include Phlex::Rails::Helpers::Routes

      ID = "ai-search-panel-body"

      #: (move: untyped, manage: untyped) -> void
      def initialize(move:, manage:)
        @move = move
        @manage = manage
      end

      #: () -> void
      def view_template
        div(id: ID, class: "flex flex-col gap-4") do
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

      #: () -> untyped
      def status_chip
        if @move.embedding_provider_ready?
          chip(t("status_active"), "bg-accent-sage/20 text-accent-sage")
        elsif Move::REAL_EMBEDDING_PROVIDERS.include?(@move.embedding_provider)
          chip(t("status_key_required"), "bg-secondary/20 text-secondary")
        else
          chip(t("status_off"), "bg-surface-container-high text-on-surface-variant")
        end
      end

      #: (untyped text, untyped color) -> untyped
      def chip(text, color)
        span(class: "#{color} rounded-full px-3 py-1 text-label-caps uppercase") { text }
      end

      #: () -> untyped
      def readonly
        span(class: "self-start rounded-full bg-surface-container-high px-4 py-2 text-body-md text-text-warm") do
          t("options.#{@move.embedding_provider}")
        end
      end

      #: (untyped key) -> untyped
      def t(key)
        I18n.t("settings.show.recognition.embeddings.#{key}")
      end
    end
  end
end
