# frozen_string_literal: true

module Views
  module Settings
    # Admin control for the per-Move semantic-search provider + its live indexing
    # status (#232/#239). Extracted from EmbeddingProviderPanel so it can be both
    # rendered on the settings page AND broadcast verbatim over Turbo Streams as a
    # re-embedding run progresses (IndexingRuns::Broadcasting). The wrapping id is
    # the broadcast replace target; it exists only in the admin (manage) branch, so
    # broadcasts are a no-op for viewers (who never see this control).
    #
    # While a run is in progress the provider pills are rendered as disabled
    # (non-submitting) chips — you can't switch provider mid-index — and re-enable
    # automatically when the completion broadcast replaces this region.
    class EmbeddingControl < Views::Base
      include Phlex::Rails::Helpers::ButtonTo
      include Phlex::Rails::Helpers::Routes

      ID = "ai-embedding-control"

      def initialize(move:)
        @move = move
        @run = move.indexing_runs.order(:created_at).last
        @locked = @run&.in_progress? || false
      end

      def view_template
        div(id: ID, class: "flex flex-col gap-3") do
          div(class: "flex flex-wrap items-center gap-1 rounded-full border border-card-border bg-card p-1") do
            Move::EMBEDDING_PROVIDERS.each { |provider| option(provider) }
          end
          needs_key_hint
          span(class: "text-body-sm text-muted") { t("keyword_note") }
          span(class: "text-body-md text-on-surface-variant") { t("reindex_note") }
          render Components::Ui::AiIndexingStatus.new(run: @run)
        end
      end

      private

      def option(provider)
        label = t("options.#{provider}")
        active = @move.embedding_provider == provider
        # A static chip (no form) when active, while indexing is running (switching
        # locked mid-index), or when a real provider has no stored key yet.
        return active_pill(label) if active
        return disabled_pill(label) if @locked || !selectable?(provider)

        button_to(
          label, move_settings_embedding_provider_path(@move), method: :patch,
                                                               params: { move: { embedding_provider: provider } },
                                                               form_class: "inline-flex", class: "#{pill} text-on-surface-variant hover:text-text-warm"
        )
      end

      def active_pill(label)
        span(class: "#{pill} bg-surface-container-high text-text-warm", aria_current: "true") { label }
      end

      def disabled_pill(label)
        span(class: "#{pill} cursor-not-allowed text-muted opacity-60", aria_disabled: "true") { label }
      end

      # fake is always selectable; a real provider needs its key stored first.
      def selectable?(provider)
        provider == "fake" || @move.embedding_api_key_for(provider).present?
      end

      # Shown when the active provider can't actually run (real, but no key).
      def needs_key_hint
        return if @move.embedding_provider == "fake" || @move.embedding_provider_ready?

        span(class: "text-body-md text-secondary") { t("needs_key") }
      end

      def pill
        "rounded-full px-6 py-2 text-sm font-semibold transition"
      end

      def t(key)
        I18n.t("settings.show.recognition.embeddings.#{key}")
      end
    end
  end
end
