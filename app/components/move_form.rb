# frozen_string_literal: true

module Components
  # A1 — Create New Move form. Exactly the spec fields: name (required),
  # optional planned date, optional origin/destination address, and unit system.
  class MoveForm < Components::Base
    include Phlex::Rails::Helpers::FormWith
    include Phlex::Rails::Helpers::Pluralize

    #: (move: untyped) -> void
    def initialize(move:)
      @move = move
    end

    #: () -> void
    def view_template
      form_with(model: @move, class: "flex flex-col gap-5") do |form|
        render_errors if @move.errors.any?

        field(form, :name, I18n.t("moves.form.name"), required: true,
                                                      placeholder: I18n.t("moves.form.name_placeholder"))
        field(form, :planned_on, I18n.t("moves.form.planned_on"), type: :date, optional: true)
        field(form, :origin_address, I18n.t("moves.form.origin"), optional: true)
        field(form, :destination_address, I18n.t("moves.form.destination"), optional: true)

        div(class: "flex flex-col gap-2") do
          form.label :unit_system, label_text(I18n.t("moves.form.unit_system")),
                     class: "text-label-caps uppercase text-muted"
          form.select :unit_system,
                      [[I18n.t("moves.unit.metric"), "metric"], [I18n.t("moves.unit.imperial"), "imperial"]],
                      {}, class: "ha-input"
        end

        div(class: "mt-2 flex flex-wrap gap-3") do
          form.submit I18n.t("moves.form.submit"), class: "ha-button ha-button-primary"
        end
      end
    end

    private

    #: (untyped form, untyped name, untyped text, ?type: untyped, ?required: untyped, ?optional: untyped, ?placeholder: untyped) -> untyped
    def field(form, name, text, type: :text, required: false, optional: false, placeholder: nil)
      div(class: "flex flex-col gap-2") do
        form.label name, label_text(text, optional: optional),
                   class: "text-label-caps uppercase text-muted"
        if type == :date
          form.date_field name, class: "ha-input"
        else
          form.text_field name, required: required, placeholder: placeholder, class: "ha-input"
        end
      end
    end

    #: (untyped text, ?optional: untyped) -> untyped
    def label_text(text, optional: false)
      optional ? "#{text} · #{I18n.t("moves.form.optional")}" : text
    end

    #: () -> untyped
    def render_errors
      div(class: "rounded-card bg-[var(--ha-error-container)] px-5 py-4 text-body-md text-error") do
        h2(class: "font-semibold") do
          plain I18n.t("moves.form.errors", count: @move.errors.count)
        end
        ul(class: "mt-2 list-disc space-y-1 pl-5") do
          @move.errors.each { |error| li { error.full_message } }
        end
      end
    end
  end
end
