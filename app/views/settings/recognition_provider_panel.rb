# frozen_string_literal: true

module Views
  module Settings
    # F3 / #185 / #242 — per-Move Recognition provider selector. Keys now live in
    # the shared AI Capability panel, so this is a pure chooser: a segmented
    # selector (each pill a button_to that switches the provider via Turbo) plus,
    # for the active real provider, an inline model override. A real provider with
    # no stored key renders disabled with a "needs key" hint (strict BYO — the
    # action rejects it too). Non-admins see the active provider read-only.
    class RecognitionProviderPanel < Views::Base
      include Phlex::Rails::Helpers::FormWith
      include Phlex::Rails::Helpers::ButtonTo
      include Phlex::Rails::Helpers::Routes

      def initialize(move:, manage:)
        @move = move
        @manage = manage
      end

      def view_template
        div(class: "flex flex-col gap-4") do
          div(class: "flex items-start justify-between gap-4") do
            div(class: "flex flex-col gap-1") do
              span(class: "text-headline-md text-text-warm") { t("title") }
              span(class: "text-body-md text-on-surface-variant") { t("subtitle") }
            end
            status_chip
          end
          @manage ? selector : provider_readonly
        end
      end

      private

      def status_chip
        if @move.recognition_ready?
          chip(t("status_active"), "bg-accent-sage/20 text-accent-sage")
        else
          chip(t("status_key_required"), "bg-secondary/20 text-secondary")
        end
      end

      def chip(text, color)
        span(class: "#{color} rounded-full px-3 py-1 text-label-caps uppercase") { text }
      end

      def selector
        div(class: "flex flex-col gap-3") do
          span(class: "text-label-caps uppercase text-muted") { t("provider_label") }
          div(class: "flex flex-wrap items-center gap-1 rounded-full border border-card-border bg-card p-1") do
            Move::RECOGNITION_PROVIDERS.each { |provider| provider_pill(provider) }
          end
          needs_key_hint
          model_form if real_active?
        end
      end

      def provider_pill(provider)
        label = t("options.#{provider}")
        return active_pill(label) if @move.recognition_provider == provider
        return disabled_pill(label) unless selectable?(provider)

        # Carry the *target* provider's stored model so switching to it preserves
        # its override instead of clearing it (the action always writes the model).
        button_to(
          label, move_settings_recognition_provider_path(@move), method: :patch,
                                                                 params: { move: { recognition_provider: provider,
                                                                                   model: @move.recognition_model_for(provider).to_s } },
                                                                 form_class: "inline-flex", class: "#{pill} text-on-surface-variant hover:text-text-warm"
        )
      end

      def active_pill(label)
        span(class: "#{pill} bg-surface-container-high text-text-warm", aria_current: "true") { label }
      end

      def disabled_pill(label)
        span(
          class: "#{pill} cursor-not-allowed text-muted opacity-60", aria_disabled: "true",
          title: t("needs_key")
        ) { label }
      end

      # fake is always selectable; a real provider needs its key stored first.
      def selectable?(provider)
        provider == "fake" || @move.recognition_api_key_for(provider).present?
      end

      def real_active?
        Move::REAL_RECOGNITION_PROVIDERS.include?(@move.recognition_provider)
      end

      def needs_key_hint
        return if selectable?(@move.recognition_provider)

        span(class: "text-body-md text-secondary") { t("needs_key") }
      end

      # Inline model override for the active real provider (#187). Submits the
      # active provider + the model so the same action records the override; blank
      # or default clears it.
      def model_form
        provider = @move.recognition_provider
        form_with(url: move_settings_recognition_provider_path(@move), method: :patch,
                  class: "mt-2 flex flex-col gap-2") do
          input(type: "hidden", name: "move[recognition_provider]", value: provider)
          span(class: "text-label-caps uppercase text-muted") { t("model_label") }
          input(
            type: "text", name: "move[model]", autocomplete: "off",
            value: @move.recognition_model_for(provider).to_s,
            placeholder: RecognitionProviders.default_model(provider),
            class: "w-full rounded-card border border-card-border bg-card px-4 py-3 text-text-warm " \
                   "placeholder:text-muted transition focus:border-accent-sage focus:outline-none " \
                   "focus:ring-2 focus:ring-accent-sage/30"
          )
          span(class: "text-body-md text-on-surface-variant") { t("model_help") }
          div { render Components::Ui::Button.new(label: t("save"), type: "submit", variant: :secondary) }
        end
      end

      def provider_readonly
        provider = @move.recognition_provider
        div(class: "flex flex-col gap-2") do
          span(class: "self-start rounded-full bg-surface-container-high px-4 py-2 text-body-md text-text-warm") do
            t("options.#{provider}")
          end
          if real_active?
            span(class: "text-body-md text-on-surface-variant") do
              "#{t("model_label")}: #{current_model(provider)}"
            end
          end
        end
      end

      def current_model(provider)
        @move.recognition_model_for(provider).presence || RecognitionProviders.default_model(provider)
      end

      def pill
        "rounded-full px-5 py-2 text-sm font-semibold transition"
      end

      def t(key)
        I18n.t("settings.show.recognition.providers.#{key}")
      end
    end
  end
end
