# frozen_string_literal: true

module Components
  # D2 — Add / rename form for a controlled-vocabulary value (rooms). The routes
  # are not resourceful (one controller, `:kind` segment), so the URL + method are
  # passed explicitly and fields are scoped to `vocabulary[...]`. This is the
  # *only* place a value is created.
  class VocabularyForm < Components::Base
    include Phlex::Rails::Helpers::FormWith

    # cancel_action: a Stimulus data-action string for an inline (no-navigation)
    #   cancel button — used when the edit form is toggled open client-side.
    # form_data / field_data: extra data attributes for the <form> and the name
    #   input (reset-form wiring on the add form; the inline-edit input target).
    def initialize(vocabulary:, record:, url:, method:, submit_label:,
                   cancel_href: nil, cancel_action: nil, compact: false, form_data: {}, field_data: {})
      @vocabulary = vocabulary
      @record = record
      @url = url
      @method = method
      @submit_label = submit_label
      @cancel_href = cancel_href
      @cancel_action = cancel_action
      @compact = compact
      @form_data = form_data
      @field_data = field_data
    end

    def view_template
      form_with(url: @url, method: @method, scope: :vocabulary, data: @form_data,
                class: "flex flex-col gap-4 sm:flex-row sm:items-end") do |form|
        div(class: "flex-grow") do
          render Components::Ui::Field.new(
            name: "vocabulary[name]", label: I18n.t("vocabularies.form.name"),
            value: @record.name, placeholder: I18n.t("vocabularies.form.name_placeholder"),
            error: @record.errors[:name].first, required: true, autofocus: @compact, data: @field_data
          )
        end
        actions(form)
      end
    end

    private

    def actions(form)
      div(class: "flex gap-3") do
        form.submit @submit_label, class: "ha-button ha-button-primary whitespace-nowrap"
        cancel_control
      end
    end

    def cancel_control
      if @cancel_action
        button(type: "button", data: { action: @cancel_action },
               class: "ha-button ha-button-secondary whitespace-nowrap") do
          I18n.t("vocabularies.form.cancel")
        end
      elsif @cancel_href
        a(href: @cancel_href, class: "ha-button ha-button-secondary whitespace-nowrap") do
          I18n.t("vocabularies.form.cancel")
        end
      end
    end
  end
end
