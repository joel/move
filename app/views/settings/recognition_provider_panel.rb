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
                    recognition_provider_masks_value: provider_masks.to_json,
                    recognition_provider_models_value: provider_models.to_json }) do
          form_with(url: move_settings_recognition_provider_path(@move), method: :patch) do
            input(type: "hidden", name: "move[recognition_provider]", value: @move.recognition_provider,
                  data: { recognition_provider_target: "providerInput" })
            provider_pills
            model_field
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

      # Inline-editable model override (#187), shown above the key field. The model
      # sits behind a toggle button (current model + "Change"); clicking it reveals
      # a free-text input pre-filled with the shown value so the choice is never
      # lost. Blank/default submits as nil (Moves::SetRecognitionProvider). Hidden
      # for the keyless "fake"; the Stimulus controller retargets it per provider.
      def model_field
        provider = @move.recognition_provider
        div(class: "mt-4 flex flex-col gap-2", hidden: provider == "fake",
            data: { recognition_provider_target: "modelWrap" }) do
          span(class: "text-label-caps uppercase text-muted") { t("model_label") }
          model_toggle(provider)
          model_input(provider)
          span(class: "text-body-md text-on-surface-variant") { t("model_help") }
        end
      end

      def model_toggle(provider)
        button(
          type: "button",
          class: "inline-flex items-center gap-2 self-start rounded-card border border-card-border " \
                 "bg-card px-4 py-3 text-text-warm transition hover:border-accent-sage",
          data: { recognition_provider_target: "modelToggle", action: "recognition-provider#editModel" }
        ) do
          span(class: "font-mono text-body-md", data: { recognition_provider_target: "modelToggleText" }) do
            current_model(provider)
          end
          span(class: "text-label-caps uppercase text-accent-sage") { "✎ #{t("model_change")}" }
        end
      end

      def model_input(provider)
        input(
          type: "text", name: "move[model]", hidden: true, autocomplete: "off",
          value: @move.recognition_model_for(provider).to_s,
          placeholder: RecognitionProviders.default_model(provider),
          class: "w-full rounded-card border border-card-border bg-card px-4 py-3 text-text-warm " \
                 "placeholder:text-muted transition focus:border-accent-sage focus:outline-none " \
                 "focus:ring-2 focus:ring-accent-sage/30",
          data: { recognition_provider_target: "modelInput" }
        )
      end

      # The model the Move would use for +provider+: its override, else the
      # adapter's default. nil for fake.
      def current_model(provider)
        @move.recognition_model_for(provider).presence || RecognitionProviders.default_model(provider)
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
        provider = @move.recognition_provider
        div(class: "flex flex-col gap-2") do
          span(class: "self-start rounded-full bg-surface-container-high px-4 py-2 text-body-md text-text-warm") do
            t("options.#{provider}")
          end
          if Move::REAL_RECOGNITION_PROVIDERS.include?(provider)
            span(class: "text-body-md text-on-surface-variant") do
              "#{t("model_label")}: #{current_model(provider)}"
            end
          end
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

      # Per-provider { default:, override: } so the Stimulus controller can retarget
      # the model toggle/input when the active provider changes (#187).
      def provider_models
        Move::REAL_RECOGNITION_PROVIDERS.index_with do |provider|
          { default: RecognitionProviders.default_model(provider),
            override: @move.recognition_model_for(provider).to_s }
        end
      end

      def t(key)
        I18n.t("settings.show.recognition.providers.#{key}")
      end
    end
  end
end
