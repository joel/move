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
          div(class: "inline-flex self-start rounded-full border border-card-border bg-card p-1") do
            option("fake", t("label_off"))
            option("openai", t("label_on"))
          end
          if @move.embedding_provider == "openai" && !@move.embedding_provider_ready?
            span(class: "text-body-md text-secondary") { t("key_required_help") }
          end
          span(class: "text-body-md text-on-surface-variant") { t("reindex_note") }
          render Components::Ui::AiIndexingStatus.new(run: @run)
        end
      end

      private

      def option(provider, label)
        active = @move.embedding_provider == provider
        # Active option, or any option while indexing is running, is a static chip
        # (no form) — switching is locked mid-index.
        if active || @locked
          span(
            class: "#{pill} #{active ? "bg-surface-container-high text-text-warm" : "text-muted"} " \
                   "#{"cursor-not-allowed opacity-60" unless active}",
            aria_current: ("true" if active), aria_disabled: ("true" unless active)
          ) { label }
        else
          button_to(
            move_settings_embedding_provider_path(@move), method: :patch,
                                                          params: { move: { embedding_provider: provider } },
                                                          class: "#{pill} text-on-surface-variant hover:text-text-warm"
          ) { label }
        end
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
