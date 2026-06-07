# frozen_string_literal: true

module Components
  # D2 — Add / rename form for a controlled-vocabulary value. The routes are not
  # resourceful (one controller, `:kind` segment), so the URL + method are
  # passed explicitly and fields are scoped to `vocabulary[...]`. For tags the
  # form also exposes the applies-to facet. Selection-only everywhere else — this
  # is the *only* place a value is created.
  class VocabularyForm < Components::Base
    include Phlex::Rails::Helpers::FormWith

    def initialize(vocabulary:, record:, url:, method:, submit_label:, cancel_href: nil, compact: false)
      @vocabulary = vocabulary
      @record = record
      @url = url
      @method = method
      @submit_label = submit_label
      @cancel_href = cancel_href
      @compact = compact
    end

    def view_template
      form_with(url: @url, method: @method, scope: :vocabulary,
                class: "flex flex-col gap-4 sm:flex-row sm:items-end") do |form|
        div(class: "flex-grow") do
          render Components::Ui::Field.new(
            name: "vocabulary[name]", label: I18n.t("vocabularies.form.name"),
            value: @record.name, placeholder: I18n.t("vocabularies.form.name_placeholder"),
            error: @record.errors[:name].first, required: true, autofocus: @compact
          )
        end
        applies_to_field if @vocabulary.applies_to?
        actions(form)
      end
    end

    private

    def applies_to_field
      div(class: "sm:w-48") do
        render Components::Ui::Select.new(
          name: "vocabulary[applies_to]", label: I18n.t("vocabularies.form.applies_to"),
          options: Tag::APPLIES_TO.map { |v| [I18n.t("vocabularies.applies_to.#{v}"), v] },
          selected: @record.applies_to, error: @record.errors[:applies_to].first
        )
      end
    end

    def actions(form)
      div(class: "flex gap-3") do
        form.submit @submit_label, class: "ha-button ha-button-primary whitespace-nowrap"
        if @cancel_href
          a(href: @cancel_href, class: "ha-button ha-button-secondary whitespace-nowrap") do
            I18n.t("vocabularies.form.cancel")
          end
        end
      end
    end
  end
end
