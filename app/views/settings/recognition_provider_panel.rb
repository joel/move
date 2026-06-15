# frozen_string_literal: true

module Views
  module Settings
    # F3 / #185 — per-Move Recognition provider chooser + bring-your-own API key.
    # Admins get the interactive selector (a Stimulus controller swaps the active
    # pill, the hidden provider field, the masked-key hint, and the Remove-key
    # target) plus a write-only password field; everyone else sees the active
    # provider read-only. Keys are never rendered in full — only "••••" + last 4.
    # Rendered inside the Settings recognition card, above the threshold slider.
    class RecognitionProviderPanel < Views::Base
      include Phlex::Rails::Helpers::FormWith
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
          @manage ? provider_form : provider_readonly
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

      def provider_form
        div(data: { controller: "recognition-provider",
                    recognition_provider_masks_value: provider_masks.to_json }) do
          form_with(url: move_settings_recognition_provider_path(@move), method: :patch) do
            input(type: "hidden", name: "move[recognition_provider]", value: @move.recognition_provider,
                  data: { recognition_provider_target: "providerInput" })
            provider_pills
            key_field
            div(class: "mt-4") do
              render Components::Ui::Button.new(label: t("save"), type: "submit")
            end
          end
          remove_key_form
        end
      end

      def provider_pills
        div(class: "flex flex-col gap-2") do
          span(class: "text-label-caps uppercase text-muted") { t("provider_label") }
          div(class: "inline-flex flex-wrap gap-1 self-start rounded-full border border-card-border bg-card p-1") do
            Move::RECOGNITION_PROVIDERS.each { |provider| provider_pill(provider) }
          end
        end
      end

      def provider_pill(provider)
        active = @move.recognition_provider == provider
        base = "rounded-full px-5 py-2 text-sm font-semibold transition"
        state = active ? "bg-surface-container-high text-text-warm" : "text-on-surface-variant hover:text-text-warm"
        button(
          type: "button", class: "#{base} #{state}", aria_current: (active ? "true" : nil),
          data: { provider: provider, recognition_provider_target: "pill",
                  action: "recognition-provider#select", recognition_provider_provider_param: provider }
        ) { t("options.#{provider}") }
      end

      # Single masked, write-only key field for the selected provider. Hidden for
      # the keyless "fake"; the hint shows the active provider's stored mask.
      def key_field
        div(class: "mt-4 flex flex-col gap-2", hidden: @move.recognition_provider == "fake",
            data: { recognition_provider_target: "keyWrap" }) do
          render Components::Ui::Field.new(
            name: "move[api_key]", type: "password", label: t("api_key_label"),
            placeholder: t("api_key_placeholder"), hint: t("api_key_help"), autocomplete: "off"
          )
          span(class: "font-mono text-body-md text-on-surface-variant",
               data: { recognition_provider_target: "hint" }) { masked_key(@move.recognition_provider) }
        end
      end

      # Separate DELETE form so a blank Save never clears a key; the Stimulus
      # controller rewrites its action to the selected provider (PROVIDER token).
      def remove_key_form
        active = @move.recognition_provider
        real = Move::REAL_RECOGNITION_PROVIDERS.include?(active)
        div(class: "mt-2", hidden: !(real && masked_key(active).present?),
            data: { recognition_provider_target: "removeWrap" }) do
          button_to(
            t("remove_key"),
            move_settings_remove_recognition_key_path(@move, provider: real ? active : "openai"),
            method: :delete,
            form: { data: { recognition_provider_target: "removeForm",
                            url_template: move_settings_remove_recognition_key_path(@move, provider: "PROVIDER") } },
            class: "text-label-caps uppercase text-secondary transition hover:underline"
          )
        end
      end

      def provider_readonly
        span(class: "self-start rounded-full bg-surface-container-high px-4 py-2 text-body-md text-text-warm") do
          t("options.#{@move.recognition_provider}")
        end
      end

      # "••••" + last 4 of the stored key, or "" when none. Admin-only surface; the
      # full key is never rendered.
      def masked_key(provider)
        key = @move.recognition_api_key_for(provider)
        key.present? ? "••••••••#{key[-4..]}" : ""
      end

      def provider_masks
        Move::REAL_RECOGNITION_PROVIDERS.index_with { |provider| masked_key(provider) }
      end

      def t(key)
        I18n.t("settings.show.recognition.providers.#{key}")
      end
    end
  end
end
