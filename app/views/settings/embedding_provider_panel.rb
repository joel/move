# frozen_string_literal: true

module Views
  module Settings
    # #232 — per-Move semantic-search (embedding) provider. A plain Off/On toggle
    # (fake/openai) that reuses the Move's OpenAI key from the recognition panel
    # above — there is no separate key field. Admins get the toggle; everyone else
    # sees the active state read-only. Turning it on enqueues a per-Move reindex.
    # Rendered inside the Settings recognition card, below the recognition panel.
    class EmbeddingProviderPanel < Views::Base
      include Phlex::Rails::Helpers::ButtonTo
      include Phlex::Rails::Helpers::Routes

      def initialize(move:, manage:)
        @move = move
        @manage = manage
      end

      def view_template
        div(class: "flex flex-col gap-4 border-b border-card-border pb-6") do
          div(class: "flex items-start justify-between gap-4") do
            div(class: "flex flex-col gap-1") do
              span(class: "text-headline-md text-text-warm") { t("title") }
              span(class: "text-body-md text-on-surface-variant") { t("subtitle") }
            end
            status_chip
          end
          @manage ? toggle : readonly
        end
      end

      private

      def status_chip
        if @move.embedding_provider_ready?
          chip(t("status_active"), "bg-accent-sage/20 text-accent-sage")
        elsif @move.embedding_provider == "openai"
          chip(t("status_key_required"), "bg-secondary/20 text-secondary")
        else
          chip(t("status_off"), "bg-surface-container-high text-on-surface-variant")
        end
      end

      def chip(text, color)
        span(class: "#{color} rounded-full px-3 py-1 text-label-caps uppercase") { text }
      end

      def toggle
        div(class: "flex flex-col gap-2") do
          div(class: "inline-flex self-start rounded-full border border-card-border bg-card p-1") do
            option("fake", t("label_off"))
            option("openai", t("label_on"))
          end
          # Openai chosen but no key yet → tell the admin how to make it real.
          if @move.embedding_provider == "openai" && !@move.embedding_provider_ready?
            span(class: "text-body-md text-secondary") { t("key_required_help") }
          end
          span(class: "text-body-md text-on-surface-variant") { t("reindex_note") }
        end
      end

      def option(provider, label)
        if @move.embedding_provider == provider
          span(class: "#{pill} bg-surface-container-high text-text-warm", aria_current: "true") { label }
        else
          button_to(
            move_settings_embedding_provider_path(@move), method: :patch,
                                                          params: { move: { embedding_provider: provider } },
                                                          class: "#{pill} text-on-surface-variant hover:text-text-warm"
          ) { label }
        end
      end

      def readonly
        label = @move.embedding_provider == "openai" ? t("label_on") : t("label_off")
        span(class: "self-start rounded-full bg-surface-container-high px-4 py-2 text-body-md text-text-warm") { label }
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
